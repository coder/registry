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
    const key = `OpenCode: ${suffix}`;
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
  skipOpencodeMock?: boolean;
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
    install_opencode: "false",
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
  if (!props?.skipOpencodeMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/opencode",
      content: await Bun.file(
        path.join(moduleDir, "testdata", "opencode-mock.sh"),
      ).text(),
    });
  }
  return { id, coderEnvVars, scripts };
};

// coder_env values reach coder_script processes through the agent environment.
const envArgs = (env: Record<string, string>) =>
  Object.entries(env).flatMap(([key, value]) => ["--env", `${key}=${value}`]);

const runScript = async (
  id: string,
  name: string,
  script: string,
  env: Record<string, string> = {},
) => {
  const target = `/tmp/coder-utils-${name}.sh`;
  await writeExecutable({ containerId: id, filePath: target, content: script });
  return execContainer(id, ["bash", "-c", target], envArgs(env));
};

const runScripts = async (
  id: string,
  scripts: ModuleScripts,
  env: Record<string, string> = {},
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

const moduleLogDir = "/home/coder/.coder-modules/coder-labs/opencode/logs";
const installLog = (id: string) =>
  readFileContainer(id, `${moduleLogDir}/install.log`);
const configPath = "/home/coder/.config/opencode/opencode.json";
const authPath = "/home/coder/.local/share/opencode/auth.json";
const managedPath = "/etc/opencode/opencode.json";

const seedFile = async (id: string, filePath: string, content: string) => {
  const encoded = Buffer.from(content).toString("base64");
  await execContainer(id, [
    "bash",
    "-c",
    `mkdir -p "$(dirname '${filePath}')" && echo '${encoded}' | base64 -d > '${filePath}'`,
  ]);
};

setDefaultTimeout(60 * 1000);

describe("opencode", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path-validates-existing-binary", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const log = await installLog(id);
    expect(log).toContain("Skipping OpenCode installation");
    expect(log).toContain("Validated existing OpenCode");
    expect(log).toContain("0.0.0-mock");
    expect(log).toContain("OpenCode module setup completed.");
    expect(log).not.toContain("agentapi");
    // Nothing is written when no config is provided.
    const cfg = await execContainer(id, ["test", "-e", configPath]);
    expect(cfg.exitCode).not.toBe(0);
  });

  test("preinstalled-binary-required-when-install-disabled", async () => {
    const { id, scripts } = await setup({ skipOpencodeMock: true });
    const resp = await runScript(id, "install", scripts.install);
    expect(resp.exitCode).not.toBe(0);
    const log = await installLog(id);
    expect(log).toContain("was not found or is not executable");
  });

  test("official-installer-is-used", async () => {
    const { id, scripts } = await setup({
      skipOpencodeMock: true,
      moduleVariables: { install_opencode: "true", opencode_version: "v1.2.3" },
    });
    await writeExecutable({
      containerId: id,
      filePath: "/tmp/opencode-installer-fixture.sh",
      content: [
        "#!/usr/bin/env bash",
        'printf "VERSION=%s ARGS=%s\\n" "$VERSION" "$*" > /tmp/opencode-installer-env',
        'mkdir -p "$HOME/.opencode/bin"',
        `cat > "$HOME/.opencode/bin/opencode" <<'EOF'`,
        "#!/bin/sh",
        'if [ "$1" = "--version" ]; then echo "1.2.3"; fi',
        "EOF",
        'chmod +x "$HOME/.opencode/bin/opencode"',
      ].join("\n"),
    });
    await writeExecutable({
      containerId: id,
      filePath: "/usr/local/bin/curl",
      content: [
        "#!/bin/bash",
        "printf '%s\\n' \"$*\" > /tmp/opencode-curl-args",
        'while [ $# -gt 0 ]; do if [ "$1" = "--output" ]; then out="$2"; fi; shift; done',
        'cp /tmp/opencode-installer-fixture.sh "$out"',
      ].join("\n"),
    });
    await runScripts(id, scripts);
    const log = await installLog(id);
    expect(log).toContain("Installed OpenCode");
    expect(log).toContain("OpenCode version: 1.2.3");
    const curlArgs = await readFileContainer(id, "/tmp/opencode-curl-args");
    expect(curlArgs).toContain("https://opencode.ai/install");
    expect(curlArgs).toContain("--retry 2");
    expect(curlArgs).toContain("--connect-timeout 10");
    expect(curlArgs).toContain("--max-time 300");
    const installerEnv = await readFileContainer(
      id,
      "/tmp/opencode-installer-env",
    );
    expect(installerEnv.trim()).toBe("VERSION=v1.2.3 ARGS=--no-modify-path");
    const bashrc = await readFileContainer(id, "/home/coder/.bashrc");
    expect(bashrc).toContain("/home/coder/.opencode/bin");
  });

  test("latest-is-passed-to-installer-as-empty-version", async () => {
    const { id, scripts } = await setup({
      skipOpencodeMock: true,
      moduleVariables: { install_opencode: "true" },
    });
    await writeExecutable({
      containerId: id,
      filePath: "/tmp/opencode-installer-fixture.sh",
      content: [
        "#!/usr/bin/env bash",
        'printf "VERSION=[%s]\\n" "$VERSION" > /tmp/opencode-installer-env',
        'mkdir -p "$HOME/.opencode/bin"',
        'printf "#!/bin/sh\\necho 9.9.9\\n" > "$HOME/.opencode/bin/opencode"',
        'chmod +x "$HOME/.opencode/bin/opencode"',
      ].join("\n"),
    });
    await writeExecutable({
      containerId: id,
      filePath: "/usr/local/bin/curl",
      content: [
        "#!/bin/bash",
        'while [ $# -gt 0 ]; do if [ "$1" = "--output" ]; then out="$2"; fi; shift; done',
        'cp /tmp/opencode-installer-fixture.sh "$out"',
      ].join("\n"),
    });
    await runScripts(id, scripts);
    const installerEnv = await readFileContainer(
      id,
      "/tmp/opencode-installer-env",
    );
    expect(installerEnv.trim()).toBe("VERSION=[]");
  });

  test("installer-download-failure-is-terminal", async () => {
    const { id, scripts } = await setup({
      skipOpencodeMock: true,
      moduleVariables: { install_opencode: "true" },
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

  test("config-json-merges-and-preserves-existing-keys", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        config_json: JSON.stringify({
          model: "anthropic/claude-sonnet-4-5",
          provider: { anthropic: { options: { timeout: 600000 } } },
        }),
      },
    });
    await seedFile(
      id,
      configPath,
      JSON.stringify({
        model: "openai/gpt-5",
        share: "manual",
        provider: { anthropic: { options: { setCacheKey: true } } },
      }),
    );
    await runScripts(id, scripts);
    const cfg = JSON.parse(await readFileContainer(id, configPath));
    expect(cfg.model).toBe("anthropic/claude-sonnet-4-5");
    expect(cfg.share).toBe("manual");
    expect(cfg.provider.anthropic.options.timeout).toBe(600000);
    expect(cfg.provider.anthropic.options.setCacheKey).toBe(true);
    expect(cfg.$schema).toBe("https://opencode.ai/config.json");
  });

  test("writes-mcp-servers-without-coder-server", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        mcp: JSON.stringify({
          playwright: {
            type: "local",
            command: ["npx", "-y", "@playwright/mcp"],
          },
        }),
      },
    });
    await runScripts(id, scripts);
    const cfg = JSON.parse(await readFileContainer(id, configPath));
    expect(cfg.mcp.playwright.command).toEqual([
      "npx",
      "-y",
      "@playwright/mcp",
    ]);
    expect(cfg.mcp.coder).toBeUndefined();
  });

  test("merges-mcp-config-existing-servers-win", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        mcp: JSON.stringify({
          shared: { type: "local", command: ["module-command"] },
          extra: { type: "local", command: ["extra-command"] },
        }),
      },
    });
    await seedFile(
      id,
      configPath,
      JSON.stringify({
        theme: "keep-me",
        mcp: {
          shared: { type: "local", command: ["existing-command"] },
          seeded: { type: "remote", url: "https://seeded.example.com" },
        },
      }),
    );
    await runScripts(id, scripts);
    const cfg = JSON.parse(await readFileContainer(id, configPath));
    expect(cfg.theme).toBe("keep-me");
    expect(cfg.mcp.shared.command).toEqual(["existing-command"]);
    expect(cfg.mcp.seeded.url).toBe("https://seeded.example.com");
    expect(cfg.mcp.extra.command).toEqual(["extra-command"]);
  });

  test("invalid-existing-config-is-backed-up", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        config_json: JSON.stringify({ share: "disabled" }),
      },
    });
    await seedFile(id, configPath, '{ // jsonc\n  "share": "auto" }');
    await runScripts(id, scripts);
    const cfg = JSON.parse(await readFileContainer(id, configPath));
    expect(cfg.share).toBe("disabled");
    const backup = await readFileContainer(id, `${configPath}.bak`);
    expect(backup).toContain("// jsonc");
  });

  test("auth-json-from-env-merges-and-is-private", async () => {
    const secret = "sk-ant-test-secret-123";
    const { id, coderEnvVars, scripts } = await setup({
      moduleVariables: {
        auth_json: JSON.stringify({
          anthropic: { type: "api", key: secret },
        }),
      },
    });
    expect(coderEnvVars["CODER_OPENCODE_AUTH_JSON"]).toContain(secret);
    expect(scripts.install).not.toContain(secret);
    expect(scripts.install).not.toContain(
      Buffer.from(coderEnvVars["CODER_OPENCODE_AUTH_JSON"]).toString("base64"),
    );
    await seedFile(
      id,
      authPath,
      JSON.stringify({
        anthropic: { type: "api", key: "old-key" },
        openai: { type: "api", key: "keep-me" },
      }),
    );
    await runScripts(id, scripts, coderEnvVars);
    const auth = JSON.parse(await readFileContainer(id, authPath));
    expect(auth.anthropic.key).toBe(secret);
    expect(auth.openai.key).toBe("keep-me");
    const mode = await execContainer(id, ["stat", "-c", "%a", authPath]);
    expect(mode.stdout.trim()).toBe("600");
    const log = await installLog(id);
    expect(log).not.toContain(secret);
  });

  test("no-auth-json-leaves-auth-file-absent", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const resp = await execContainer(id, ["test", "-e", authPath]);
    expect(resp.exitCode).not.toBe(0);
  });

  test("managed-settings-written-as-root", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        managed_settings: JSON.stringify({ share: "disabled" }),
      },
    });
    await runScripts(id, scripts);
    const managed = JSON.parse(await readFileContainer(id, managedPath));
    expect(managed.share).toBe("disabled");
    const owner = await execContainer(id, ["stat", "-c", "%U %a", managedPath]);
    expect(owner.stdout.trim()).toBe("root 644");
    const log = await installLog(id);
    expect(log).toContain(`Wrote OpenCode managed settings to ${managedPath}`);
  });

  test("managed-settings-absent-when-unset", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const resp = await execContainer(id, ["test", "-e", managedPath]);
    expect(resp.exitCode).not.toBe(0);
    const log = await installLog(id);
    expect(log).not.toContain("managed settings");
  });

  test("pre-post-install-scripts", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        pre_install_script: "#!/bin/bash\necho 'opencode-pre-install-script'",
        post_install_script: "#!/bin/bash\necho 'opencode-post-install-script'",
      },
    });
    await runScripts(id, scripts);
    expect(
      await readFileContainer(id, `${moduleLogDir}/pre_install.log`),
    ).toContain("opencode-pre-install-script");
    expect(
      await readFileContainer(id, `${moduleLogDir}/post_install.log`),
    ).toContain("opencode-post-install-script");
  });
});
