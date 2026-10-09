import {
  test,
  afterEach,
  describe,
  setDefaultTimeout,
  beforeAll,
  expect,
} from "bun:test";
import {
  execContainer,
  readFileContainer,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  TerraformState,
} from "~test";
import {
  extractCoderEnvVars,
  writeExecutable,
} from "../../../coder/modules/agentapi/test-util";
import path from "path";

interface ModuleScripts {
  pre_install?: string;
  install: string;
  post_install?: string;
}

const SCRIPT_SUFFIXES = [
  "Pre-Install Script",
  "Install Script",
  "Post-Install Script",
] as const;

const collectScripts = (state: TerraformState): ModuleScripts => {
  const byDisplayName: Record<string, string> = {};
  for (const resource of state.resources) {
    if (resource.type !== "coder_script") continue;
    for (const instance of resource.instances) {
      const attrs = instance.attributes as Record<string, unknown>;
      const displayName = attrs.display_name as string | undefined;
      const script = attrs.script as string | undefined;
      if (displayName && script) {
        byDisplayName[displayName] = script;
      }
    }
  }
  const scripts: Partial<ModuleScripts> = {};
  for (const suffix of SCRIPT_SUFFIXES) {
    const key = `Amp: ${suffix}`;
    if (!(key in byDisplayName)) continue;
    switch (suffix) {
      case "Pre-Install Script":
        scripts.pre_install = byDisplayName[key];
        break;
      case "Install Script":
        scripts.install = byDisplayName[key];
        break;
      case "Post-Install Script":
        scripts.post_install = byDisplayName[key];
        break;
    }
  }
  if (!scripts.install) {
    throw new Error("install script not found in terraform state");
  }
  return scripts as ModuleScripts;
};

let cleanupFunctions: (() => Promise<void>)[] = [];
const registerCleanup = (cleanup: () => Promise<void>) => {
  cleanupFunctions.push(cleanup);
};
afterEach(async () => {
  const cleanupFnsCopy = cleanupFunctions.slice().reverse();
  cleanupFunctions = [];
  for (const cleanup of cleanupFnsCopy) {
    try {
      await cleanup();
    } catch (error) {
      console.error("Error during cleanup:", error);
    }
  }
});

interface SetupProps {
  skipAmpMock?: boolean;
  moduleVariables?: Record<string, string>;
}

const projectDir = "/home/coder/project";

const setup = async (
  props?: SetupProps,
): Promise<{
  id: string;
  coderEnvVars: Record<string, string>;
  scripts: ModuleScripts;
}> => {
  const moduleDir = path.resolve(import.meta.dir);
  const state = await runTerraformApply(moduleDir, {
    agent_id: "foo",
    workdir: projectDir,
    install_amp: "false",
    ...props?.moduleVariables,
  });
  const scripts = collectScripts(state);
  const coderEnvVars = extractCoderEnvVars(state);

  const id = await runContainer("codercom/enterprise-node:latest");
  registerCleanup(async () => {
    if (process.env["DEBUG"] === "true" || process.env["DEBUG"] === "1") {
      console.log(`Not removing container ${id} in debug mode`);
      return;
    }
    await removeContainer(id);
  });

  await writeExecutable({
    containerId: id,
    filePath: "/usr/bin/coder",
    content: "#!/bin/bash\nexit 0\n",
  });
  if (!props?.skipAmpMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/amp",
      content: await Bun.file(
        path.join(moduleDir, "testdata", "amp-mock.sh"),
      ).text(),
    });
  }
  return { id, coderEnvVars, scripts };
};

const runScript = async (id: string, name: string, script: string) => {
  const target = `/tmp/coder-utils-${name}.sh`;
  await writeExecutable({ containerId: id, filePath: target, content: script });
  return execContainer(id, ["bash", "-c", target]);
};

const runScripts = async (id: string, scripts: ModuleScripts) => {
  const ordered: [string, string | undefined][] = [
    ["pre_install", scripts.pre_install],
    ["install", scripts.install],
    ["post_install", scripts.post_install],
  ];
  for (const [name, script] of ordered) {
    if (!script) continue;
    const resp = await runScript(id, name, script);
    if (resp.exitCode !== 0) {
      console.log(`script ${name} failed:`);
      console.log(resp.stdout);
      console.log(resp.stderr);
      throw new Error(`coder-utils ${name} script exited ${resp.exitCode}`);
    }
  }
};

const moduleLogDir =
  "/home/coder/.coder-modules/coder-labs/sourcegraph-amp/logs";
const installLog = (id: string) =>
  readFileContainer(id, `${moduleLogDir}/install.log`);
const settingsPath = "/home/coder/.config/amp/settings.json";
const managedSettingsPath = "/etc/ampcode/managed-settings.json";

const seedSettings = (id: string, content: string) =>
  execContainer(id, [
    "bash",
    "-c",
    `mkdir -p /home/coder/.config/amp && cat > ${settingsPath} <<'EOF'\n${content}\nEOF`,
  ]);

// Installer fixture that drops a fake amp binary where the real installer does.
const installerFixture = [
  "#!/usr/bin/env bash",
  'printf "%s" "${AMP_VERSION:-}" > /tmp/amp-installer-version',
  'mkdir -p "$HOME/.amp/bin" "$HOME/.local/bin"',
  `cat > "$HOME/.amp/bin/amp" <<'EOF'`,
  "#!/bin/sh",
  'if [ "$1" = "--version" ]; then echo "0.0.1790769659-g954f35 (released 2026-09-30T12:00:59.000Z, 1m ago)"; fi',
  "EOF",
  'chmod +x "$HOME/.amp/bin/amp"',
  'ln -sf "$HOME/.amp/bin/amp" "$HOME/.local/bin/amp"',
].join("\n");

const mockCurl = async (id: string, exitCode = 0) => {
  await writeExecutable({
    containerId: id,
    filePath: "/tmp/amp-installer-fixture.sh",
    content: installerFixture,
  });
  await writeExecutable({
    containerId: id,
    filePath: "/usr/local/bin/curl",
    content:
      exitCode === 0
        ? [
            "#!/bin/bash",
            "printf '%s\\n' \"$*\" > /tmp/amp-curl-args",
            'while [ $# -gt 0 ]; do if [ "$1" = "--output" ]; then out="$2"; fi; shift; done',
            'cp /tmp/amp-installer-fixture.sh "$out"',
          ].join("\n")
        : `#!/bin/bash\nexit ${exitCode}\n`,
  });
};

setDefaultTimeout(60 * 1000);

describe("sourcegraph-amp", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path-validates-existing-binary", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const log = await installLog(id);
    expect(log).toContain("Skipping Amp CLI installation");
    expect(log).toContain("Validated existing Amp CLI");
    expect(log).toContain("0.0.1700000000-gmock00");
    expect(log).toContain("Amp module setup completed.");
    expect(log).not.toContain("agentapi");
    // No settings are written when nothing is configured.
    const settings = await execContainer(id, ["test", "-e", settingsPath]);
    expect(settings.exitCode).not.toBe(0);
  });

  test("preinstalled-binary-required-when-install-disabled", async () => {
    const { id, scripts } = await setup({ skipAmpMock: true });
    const resp = await runScript(id, "install", scripts.install);
    expect(resp.exitCode).not.toBe(0);
    const log = await installLog(id);
    expect(log).toContain("was not found or is not executable");
  });

  test("official-installer-is-used", async () => {
    const { id, scripts } = await setup({
      skipAmpMock: true,
      moduleVariables: {
        install_amp: "true",
        amp_version: "0.0.1790769659-g954f35",
      },
    });
    await mockCurl(id);
    await runScripts(id, scripts);
    const log = await installLog(id);
    expect(log).toContain("Installed Amp CLI");
    expect(log).toContain("0.0.1790769659-g954f35");
    const curlArgs = await readFileContainer(id, "/tmp/amp-curl-args");
    expect(curlArgs).toContain("https://ampcode.com/install.sh");
    expect(curlArgs).toContain("--retry 2");
    expect(curlArgs).toContain("--connect-timeout 10");
    expect(curlArgs).toContain("--max-time 300");
    const version = await readFileContainer(id, "/tmp/amp-installer-version");
    expect(version).toBe("0.0.1790769659-g954f35");
  });

  test("existing-binary-skips-installer", async () => {
    const { id, scripts } = await setup({
      moduleVariables: { install_amp: "true" },
    });
    await mockCurl(id, 22);
    await runScripts(id, scripts);
    const log = await installLog(id);
    expect(log).toContain("Amp CLI already installed");
  });

  test("pinned-version-mismatch-reinstalls", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        install_amp: "true",
        amp_version: "0.0.1790769659-g954f35",
      },
    });
    await mockCurl(id);
    // The fixture links ~/.local/bin/amp, which the script puts ahead of /usr/bin.
    await runScripts(id, scripts);
    const log = await installLog(id);
    expect(log).toContain(
      "Amp CLI 0.0.1700000000-gmock00 is installed; installing requested 0.0.1790769659-g954f35",
    );
    expect(log).toContain("Installed Amp CLI");
  });

  test("installer-download-failure-is-terminal", async () => {
    const { id, scripts } = await setup({
      skipAmpMock: true,
      moduleVariables: { install_amp: "true" },
    });
    await mockCurl(id, 22);
    const resp = await runScript(id, "install", scripts.install);
    expect(resp.exitCode).not.toBe(0);
    const log = await installLog(id);
    expect(log).toContain("could not be downloaded");
  });

  test("workdir-created", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const dir = await execContainer(id, ["test", "-d", projectDir]);
    expect(dir.exitCode).toBe(0);
  });

  test("instruction-prompt", async () => {
    const prompt = "Start every response with `amp > `";
    const { id, scripts } = await setup({
      moduleVariables: { instruction_prompt: prompt },
    });
    await runScripts(id, scripts);
    const agents = await readFileContainer(
      id,
      "/home/coder/.config/amp/AGENTS.md",
    );
    expect(agents.trim()).toBe(prompt);
  });

  test("amp-settings-merge-preserves-unrelated-keys", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        amp_settings: JSON.stringify({
          "amp.dangerouslyAllowAll": true,
          "amp.showCosts": false,
        }),
      },
    });
    await seedSettings(
      id,
      JSON.stringify({
        "amp.showCosts": true,
        "amp.notifications.enabled": false,
        "amp.mcpServers": { seeded: { command: "seeded-command" } },
      }),
    );
    await runScripts(id, scripts);
    const settings = JSON.parse(await readFileContainer(id, settingsPath));
    expect(settings["amp.dangerouslyAllowAll"]).toBe(true);
    expect(settings["amp.showCosts"]).toBe(false);
    expect(settings["amp.notifications.enabled"]).toBe(false);
    expect(settings["amp.mcpServers"].seeded.command).toBe("seeded-command");
  });

  test("writes-mcp-servers-without-coder-server", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        mcp: JSON.stringify({
          playwright: { command: "npx", args: ["-y", "@playwright/mcp"] },
        }),
      },
    });
    await runScripts(id, scripts);
    const settings = JSON.parse(await readFileContainer(id, settingsPath));
    expect(settings["amp.mcpServers"].playwright.command).toBe("npx");
    expect(settings["amp.mcpServers"].coder).toBeUndefined();
    const mode = await execContainer(id, ["stat", "-c", "%a", settingsPath]);
    expect(mode.stdout.trim()).toBe("600");
  });

  test("merges-mcp-config-existing-servers-win", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        mcp: JSON.stringify({
          shared: { command: "module-command" },
          extra: { command: "extra-command" },
        }),
      },
    });
    await seedSettings(
      id,
      JSON.stringify({
        "amp.showCosts": false,
        "amp.mcpServers": {
          shared: { command: "existing-command" },
          seeded: { command: "seeded-command" },
        },
      }),
    );
    await runScripts(id, scripts);
    const settings = JSON.parse(await readFileContainer(id, settingsPath));
    const servers = settings["amp.mcpServers"];
    expect(servers.shared.command).toBe("existing-command");
    expect(servers.seeded.command).toBe("seeded-command");
    expect(servers.extra.command).toBe("extra-command");
    expect(settings["amp.showCosts"]).toBe(false);
  });

  test("jsonc-settings-are-left-untouched", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        mcp: JSON.stringify({ extra: { command: "x" } }),
      },
    });
    const jsonc = '{\n  // user comment\n  "amp.showCosts": false,\n}';
    await seedSettings(id, jsonc);
    await runScripts(id, scripts);
    const settings = await readFileContainer(id, settingsPath);
    expect(settings.trim()).toBe(jsonc);
    const log = await installLog(id);
    expect(log).toContain("is not a strict JSON object");
  });

  test("managed-settings-written-as-root", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        managed_settings: JSON.stringify({
          "amp.updates.mode": "disabled",
          "amp.mcpPermissions": [
            { matches: { command: "*" }, action: "reject" },
          ],
        }),
      },
    });
    await runScripts(id, scripts);
    const managed = JSON.parse(
      await readFileContainer(id, managedSettingsPath),
    );
    expect(managed["amp.updates.mode"]).toBe("disabled");
    expect(managed["amp.mcpPermissions"][0].action).toBe("reject");
    const stat = await execContainer(id, [
      "stat",
      "-c",
      "%U %a",
      managedSettingsPath,
    ]);
    expect(stat.stdout.trim()).toBe("root 644");
    const log = await installLog(id);
    expect(log).toContain(
      `Wrote Amp managed settings to ${managedSettingsPath}`,
    );
  });

  test("managed-settings-absent-when-unset", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const resp = await execContainer(id, ["test", "-e", managedSettingsPath]);
    expect(resp.exitCode).not.toBe(0);
  });

  test("api-key-env-var-not-in-script", async () => {
    const apiKey = "sgamp_test-api-key-123";
    const { coderEnvVars, scripts } = await setup({
      moduleVariables: { amp_api_key: apiKey },
    });
    expect(coderEnvVars["AMP_API_KEY"]).toBe(apiKey);
    expect(scripts.install).not.toContain(apiKey);
    expect(scripts.install).not.toContain(
      Buffer.from(apiKey).toString("base64"),
    );
  });

  test("pre-post-install-scripts", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        pre_install_script: "#!/bin/bash\necho 'amp-pre-install-script'",
        post_install_script: "#!/bin/bash\necho 'amp-post-install-script'",
      },
    });
    await runScripts(id, scripts);
    expect(
      await readFileContainer(id, `${moduleLogDir}/pre_install.log`),
    ).toContain("amp-pre-install-script");
    expect(
      await readFileContainer(id, `${moduleLogDir}/post_install.log`),
    ).toContain("amp-post-install-script");
  });
});
