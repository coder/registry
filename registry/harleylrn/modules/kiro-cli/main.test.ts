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
    const key = `Kiro CLI: ${suffix}`;
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
  skipKiroMock?: boolean;
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
    install_kiro_cli: "false",
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
  if (!props?.skipKiroMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/kiro-cli",
      content: await Bun.file(
        path.join(moduleDir, "testdata", "kiro-cli-mock.sh"),
      ).text(),
    });
  }
  return { id, coderEnvVars, scripts };
};

const envPrefix = (env?: Record<string, string>) =>
  Object.entries(env ?? {})
    .map(([key, value]) => `export ${key}="${value.replace(/"/g, '\\"')}" && `)
    .join("");

const runScript = async (
  id: string,
  name: string,
  script: string,
  env?: Record<string, string>,
) => {
  const target = `/tmp/coder-utils-${name}.sh`;
  await writeExecutable({ containerId: id, filePath: target, content: script });
  return execContainer(id, ["bash", "-c", `${envPrefix(env)}${target}`]);
};

const runScripts = async (
  id: string,
  scripts: ModuleScripts,
  env?: Record<string, string>,
) => {
  const ordered: [string, string | undefined][] = [
    ["pre_install", scripts.pre_install],
    ["install", scripts.install],
    ["post_install", scripts.post_install],
  ];
  for (const [name, script] of ordered) {
    if (!script) continue;
    const resp = await runScript(id, name, script, env);
    if (resp.exitCode !== 0) {
      console.log(`script ${name} failed:`);
      console.log(resp.stdout);
      console.log(resp.stderr);
      throw new Error(`coder-utils ${name} script exited ${resp.exitCode}`);
    }
  }
};

// Records curl arguments and copies the given fixture to --output.
const writeCurlMock = async (id: string, fixture: string) => {
  await writeExecutable({
    containerId: id,
    filePath: "/usr/local/bin/curl",
    content: [
      "#!/bin/bash",
      "printf '%s\\n' \"$*\" >> /tmp/kiro-curl-args",
      'while [ $# -gt 0 ]; do if [ "$1" = "--output" ]; then out="$2"; fi; shift; done',
      `cp ${fixture} "$out"`,
    ].join("\n"),
  });
};

const fakeKiroInstall = (version: string) =>
  [
    'mkdir -p "$HOME/.local/bin"',
    `printf '#!/bin/sh\\necho "kiro-cli ${version}"\\n' > "$HOME/.local/bin/kiro-cli"`,
    'chmod +x "$HOME/.local/bin/kiro-cli"',
  ].join("\n");

// Builds a release-archive fixture with the same layout as
// kirocli-<arch>-linux.zip (kirocli/install.sh).
const writeArchiveFixture = async (id: string, version: string) => {
  await execContainer(id, ["mkdir", "-p", "/tmp/kiro-fixture/kirocli"]);
  await writeExecutable({
    containerId: id,
    filePath: "/tmp/kiro-fixture/kirocli/install.sh",
    content: [
      "#!/bin/sh",
      'echo "KIRO_CLI_SKIP_SETUP=$KIRO_CLI_SKIP_SETUP" > /tmp/kiro-archive-install-env',
      fakeKiroInstall(version),
    ].join("\n"),
  });
  const resp = await execContainer(id, [
    "bash",
    "-c",
    "cd /tmp/kiro-fixture && python3 -m zipfile -c /tmp/kiro-archive.zip kirocli",
  ]);
  expect(resp.exitCode).toBe(0);
};

const moduleLogDir = "/home/coder/.coder-modules/harleylrn/kiro-cli/logs";
const installLog = (id: string) =>
  readFileContainer(id, `${moduleLogDir}/install.log`);
const mcpConfigPath = "/home/coder/.kiro/settings/mcp.json";
const cliSettingsPath = "/home/coder/.kiro/settings/cli.json";

setDefaultTimeout(60 * 1000);

describe("kiro-cli", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path-validates-existing-binary", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const log = await installLog(id);
    expect(log).toContain("Skipping Kiro CLI installation");
    expect(log).toContain("Validated existing Kiro CLI");
    expect(log).toContain("Kiro CLI module setup completed.");
    expect(log).not.toContain("agentapi");
  });

  test("preinstalled-binary-required-when-install-disabled", async () => {
    const { id, scripts } = await setup({ skipKiroMock: true });
    const resp = await runScript(id, "install", scripts.install);
    expect(resp.exitCode).not.toBe(0);
    const log = await installLog(id);
    expect(log).toContain("was not found or is not executable");
  });

  test("official-installer-is-used-for-latest", async () => {
    const { id, scripts } = await setup({
      skipKiroMock: true,
      moduleVariables: { install_kiro_cli: "true" },
    });
    await writeExecutable({
      containerId: id,
      filePath: "/tmp/kiro-installer-fixture.sh",
      content: ["#!/usr/bin/env bash", fakeKiroInstall("2.26.0-fixture")].join(
        "\n",
      ),
    });
    await writeCurlMock(id, "/tmp/kiro-installer-fixture.sh");
    await runScripts(id, scripts);
    const log = await installLog(id);
    expect(log).toContain("Installed Kiro CLI");
    expect(log).toContain("2.26.0-fixture");
    const curlArgs = await readFileContainer(id, "/tmp/kiro-curl-args");
    expect(curlArgs).toContain("https://cli.kiro.dev/install");
    expect(curlArgs).toContain("--retry 2");
    expect(curlArgs).toContain("--connect-timeout 10");
    expect(curlArgs).toContain("--max-time 300");
  });

  test("pinned-version-uses-release-archive", async () => {
    const { id, scripts } = await setup({
      skipKiroMock: true,
      moduleVariables: { install_kiro_cli: "true", kiro_cli_version: "2.25.0" },
    });
    await writeArchiveFixture(id, "2.25.0");
    await writeCurlMock(id, "/tmp/kiro-archive.zip");
    await runScripts(id, scripts);
    const log = await installLog(id);
    expect(log).toContain("Installed Kiro CLI");
    expect(log).toContain("kiro-cli 2.25.0");
    const curlArgs = await readFileContainer(id, "/tmp/kiro-curl-args");
    expect(curlArgs).toMatch(
      /https:\/\/prod\.download\.cli\.kiro\.dev\/stable\/2\.25\.0\/kirocli-(x86_64|aarch64)-linux\.zip/,
    );
    expect(curlArgs).not.toContain("cli.kiro.dev/install");
    const env = await readFileContainer(id, "/tmp/kiro-archive-install-env");
    expect(env.trim()).toBe("KIRO_CLI_SKIP_SETUP=1");
  });

  test("custom-install-url-is-used-for-latest", async () => {
    const { id, scripts } = await setup({
      skipKiroMock: true,
      moduleVariables: {
        install_kiro_cli: "true",
        kiro_install_url: "https://mirror.example.com/kiro/",
      },
    });
    await writeArchiveFixture(id, "2.26.0");
    await writeCurlMock(id, "/tmp/kiro-archive.zip");
    await runScripts(id, scripts);
    const curlArgs = await readFileContainer(id, "/tmp/kiro-curl-args");
    expect(curlArgs).toMatch(
      /https:\/\/mirror\.example\.com\/kiro\/latest\/kirocli-(x86_64|aarch64)-linux\.zip/,
    );
  });

  test("matching-installed-version-is-not-reinstalled", async () => {
    const { id, scripts } = await setup({
      moduleVariables: { install_kiro_cli: "true", kiro_cli_version: "2.26.0" },
    });
    await writeExecutable({
      containerId: id,
      filePath: "/usr/local/bin/curl",
      content: "#!/bin/bash\necho called > /tmp/kiro-curl-called\nexit 22\n",
    });
    await runScripts(id, scripts);
    const log = await installLog(id);
    expect(log).toContain("Kiro CLI already installed (2.26.0)");
    const called = await execContainer(id, [
      "test",
      "-e",
      "/tmp/kiro-curl-called",
    ]);
    expect(called.exitCode).not.toBe(0);
  });

  test("installer-download-failure-is-terminal", async () => {
    const { id, scripts } = await setup({
      skipKiroMock: true,
      moduleVariables: { install_kiro_cli: "true" },
    });
    await writeExecutable({
      containerId: id,
      filePath: "/usr/local/bin/curl",
      content: "#!/bin/bash\nexit 22\n",
    });
    const resp = await runScript(id, "install", scripts.install);
    expect(resp.exitCode).not.toBe(0);
    const log = await installLog(id);
    expect(log).toContain("could not be downloaded");
  });

  test("workdir-is-created", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const dir = await execContainer(id, ["test", "-d", projectDir]);
    expect(dir.exitCode).toBe(0);
  });

  test("writes-mcp-servers-without-coder-server", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        mcp: JSON.stringify({
          mcpServers: {
            playwright: { command: "npx", args: ["-y", "@playwright/mcp"] },
          },
        }),
      },
    });
    await runScripts(id, scripts);
    const mcp = JSON.parse(await readFileContainer(id, mcpConfigPath));
    expect(mcp.mcpServers.playwright.command).toBe("npx");
    expect(mcp.mcpServers.coder).toBeUndefined();
  });

  test("merges-mcp-config-existing-servers-win", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        mcp: JSON.stringify({
          mcpServers: {
            shared: { command: "module-command" },
            extra: { command: "extra-command" },
          },
        }),
      },
    });
    const seed = JSON.stringify({
      mcpServers: {
        shared: { command: "existing-command" },
        seeded: { command: "seeded-command" },
      },
    });
    await execContainer(id, [
      "bash",
      "-c",
      `mkdir -p /home/coder/.kiro/settings && echo '${seed}' > ${mcpConfigPath}`,
    ]);
    await runScripts(id, scripts);
    const mcp = JSON.parse(await readFileContainer(id, mcpConfigPath));
    expect(mcp.mcpServers.shared.command).toBe("existing-command");
    expect(mcp.mcpServers.seeded.command).toBe("seeded-command");
    expect(mcp.mcpServers.extra.command).toBe("extra-command");
  });

  test("invalid-existing-mcp-config-is-backed-up", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        mcp: JSON.stringify({ mcpServers: { extra: { command: "x" } } }),
      },
    });
    await execContainer(id, [
      "bash",
      "-c",
      `mkdir -p /home/coder/.kiro/settings && echo '{ // jsonc' > ${mcpConfigPath}`,
    ]);
    await runScripts(id, scripts);
    const mcp = JSON.parse(await readFileContainer(id, mcpConfigPath));
    expect(mcp.mcpServers.extra.command).toBe("x");
    const backup = await readFileContainer(id, `${mcpConfigPath}.bak`);
    expect(backup).toContain("// jsonc");
  });

  test("agent-config-written-and-set-as-default", async () => {
    const agentConfig = {
      name: "coder-agent",
      description: "Custom agent",
      prompt: "You are helpful.",
      tools: ["read", "write"],
      includeMcpJson: true,
    };
    const { id, scripts } = await setup({
      moduleVariables: { agent_config: JSON.stringify(agentConfig) },
    });
    const seed = JSON.stringify({
      "chat.defaultModel": "user-picked-model",
      "chat.defaultAgent": "old-agent",
    });
    await execContainer(id, [
      "bash",
      "-c",
      `mkdir -p /home/coder/.kiro/settings && echo '${seed}' > ${cliSettingsPath}`,
    ]);
    await runScripts(id, scripts);
    const agent = JSON.parse(
      await readFileContainer(id, "/home/coder/.kiro/agents/coder-agent.json"),
    );
    expect(agent).toEqual(agentConfig);
    const settings = JSON.parse(await readFileContainer(id, cliSettingsPath));
    expect(settings["chat.defaultAgent"]).toBe("coder-agent");
    expect(settings["chat.defaultModel"]).toBe("user-picked-model");
  });

  test("no-agent-config-leaves-settings-untouched", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const resp = await execContainer(id, [
      "bash",
      "-c",
      "test -e /home/coder/.kiro && echo EXISTS || echo ABSENT",
    ]);
    expect(resp.stdout.trim()).toBe("ABSENT");
  });

  test("auth-tarball-is-extracted-from-env", async () => {
    const { id, scripts } = await setup();
    // tar -I zstd pipes through `zstd -d`; a passthrough keeps the fixture
    // independent of zstd being installed in the image.
    await writeExecutable({
      containerId: id,
      filePath: "/usr/local/bin/zstd",
      content: "#!/bin/sh\nexec cat\n",
    });
    const tarball = await execContainer(id, [
      "bash",
      "-c",
      "mkdir -p /tmp/auth && echo fake-auth > /tmp/auth/data.sqlite3 && tar -C /tmp/auth -cf - . | base64 -w0",
    ]);
    expect(tarball.exitCode).toBe(0);
    await execContainer(id, [
      "bash",
      "-c",
      "mkdir -p /home/coder/.local/share/kiro-cli && echo stale > /home/coder/.local/share/kiro-cli/stale",
    ]);
    await runScripts(id, scripts, {
      KIRO_CLI_AUTH_TARBALL: tarball.stdout.trim(),
    });
    const db = await readFileContainer(
      id,
      "/home/coder/.local/share/kiro-cli/data.sqlite3",
    );
    expect(db.trim()).toBe("fake-auth");
    const stale = await execContainer(id, [
      "test",
      "-e",
      "/home/coder/.local/share/kiro-cli/stale",
    ]);
    expect(stale.exitCode).not.toBe(0);
  });

  test("auth-tarball-requires-zstd", async () => {
    const { id, scripts } = await setup();
    const resp = await runScript(id, "install", scripts.install, {
      KIRO_CLI_AUTH_TARBALL: "dGVzdA==",
    });
    expect(resp.exitCode).not.toBe(0);
    const log = await installLog(id);
    expect(log).toContain("zstd is required");
  });

  test("secrets-are-env-vars-not-in-script", async () => {
    const apiKey = "ksk_test-kiro-api-key-123";
    const authTarball = "dGVzdEF1dGhUYXJiYWxs";
    const { coderEnvVars, scripts } = await setup({
      moduleVariables: { api_key: apiKey, auth_tarball: authTarball },
    });
    expect(coderEnvVars["KIRO_API_KEY"]).toBe(apiKey);
    expect(coderEnvVars["KIRO_CLI_AUTH_TARBALL"]).toBe(authTarball);
    expect(scripts.install).not.toContain(apiKey);
    expect(scripts.install).not.toContain(
      Buffer.from(apiKey).toString("base64"),
    );
    expect(scripts.install).not.toContain(authTarball);
  });

  test("pre-post-install-scripts", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        pre_install_script: "#!/bin/bash\necho 'kiro-pre-install-script'",
        post_install_script: "#!/bin/bash\necho 'kiro-post-install-script'",
      },
    });
    await runScripts(id, scripts);
    expect(
      await readFileContainer(id, `${moduleLogDir}/pre_install.log`),
    ).toContain("kiro-pre-install-script");
    expect(
      await readFileContainer(id, `${moduleLogDir}/post_install.log`),
    ).toContain("kiro-post-install-script");
  });
});
