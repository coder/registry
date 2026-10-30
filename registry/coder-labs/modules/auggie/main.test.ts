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
  const scripts: ModuleScripts = {
    pre_install: byDisplayName["Auggie: Pre-Install Script"],
    install: byDisplayName["Auggie: Install Script"],
    post_install: byDisplayName["Auggie: Post-Install Script"],
  };
  if (!scripts.install) {
    throw new Error("install script not found in terraform state");
  }
  return scripts;
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
  skipAuggieMock?: boolean;
  moduleVariables?: Record<string, string>;
}

const projectDir = "/home/coder/project";
const moduleDir = path.resolve(import.meta.dir);

const setup = async (
  props?: SetupProps,
): Promise<{
  id: string;
  coderEnvVars: Record<string, string>;
  scripts: ModuleScripts;
}> => {
  const state = await runTerraformApply(moduleDir, {
    agent_id: "foo",
    workdir: projectDir,
    install_auggie: "false",
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
  if (!props?.skipAuggieMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/auggie",
      content: await auggieMock(),
    });
  }
  return { id, coderEnvVars, scripts };
};

const auggieMock = () =>
  Bun.file(path.join(moduleDir, "testdata", "auggie-mock.sh")).text();

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

const moduleLogDir = "/home/coder/.coder-modules/coder-labs/auggie/logs";
const installLog = (id: string) =>
  readFileContainer(id, `${moduleLogDir}/install.log`);
const settingsPath = "/home/coder/.augment/settings.json";
const rulesPath = "/home/coder/.augment/rules/coder-module.md";

const seedFile = async (id: string, filePath: string, content: string) => {
  const encoded = Buffer.from(content).toString("base64");
  await execContainer(id, [
    "bash",
    "-c",
    `mkdir -p "$(dirname '${filePath}')" && echo '${encoded}' | base64 -d > '${filePath}'`,
  ]);
};

// Replaces npm with a stub that records its arguments and installs the
// Auggie mock into the npm-global prefix.
const mockNpm = async (id: string) => {
  await writeExecutable({
    containerId: id,
    filePath: "/tmp/auggie-mock-fixture.sh",
    content: await auggieMock(),
  });
  await writeExecutable({
    containerId: id,
    filePath: "/usr/local/bin/npm",
    content: [
      "#!/bin/bash",
      'echo "$*" >> /tmp/npm-calls',
      'if [ "$1" = "--version" ]; then echo 11.0.0; fi',
      'if [ "$1" = "install" ]; then',
      '  mkdir -p "$HOME/.npm-global/bin"',
      '  cp /tmp/auggie-mock-fixture.sh "$HOME/.npm-global/bin/auggie"',
      '  chmod +x "$HOME/.npm-global/bin/auggie"',
      "fi",
    ].join("\n"),
  });
};

setDefaultTimeout(60 * 1000);

describe("auggie", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path-validates-existing-binary", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const log = await installLog(id);
    expect(log).toContain("Skipping Auggie CLI installation");
    expect(log).toContain("Validated existing Auggie CLI");
    expect(log).toContain("Auggie CLI version: 0.36.0 (commit mock)");
    expect(log).toContain("Auggie module setup completed.");
    expect(log).not.toContain("agentapi");
    const settings = await execContainer(id, ["test", "-e", settingsPath]);
    expect(settings.exitCode).not.toBe(0);
    const rules = await execContainer(id, ["test", "-e", rulesPath]);
    expect(rules.exitCode).not.toBe(0);
  });

  test("preinstalled-binary-required-when-install-disabled", async () => {
    const { id, scripts } = await setup({ skipAuggieMock: true });
    const resp = await runScript(id, "install", scripts.install);
    expect(resp.exitCode).not.toBe(0);
    const log = await installLog(id);
    expect(log).toContain("was not found or is not executable");
  });

  test("npm-installs-pinned-version", async () => {
    const { id, scripts } = await setup({
      skipAuggieMock: true,
      moduleVariables: { install_auggie: "true", auggie_version: "0.35.0" },
    });
    await mockNpm(id);
    await execContainer(id, ["mkdir", "-p", "/tmp/coder-bin"]);
    await runScripts(id, scripts, { CODER_SCRIPT_BIN_DIR: "/tmp/coder-bin" });
    const calls = await readFileContainer(id, "/tmp/npm-calls");
    expect(calls).toContain("config set prefix /home/coder/.npm-global");
    expect(calls).toContain("install -g @augmentcode/auggie@0.35.0");
    const log = await installLog(id);
    expect(log).toContain("Installed Auggie CLI");
    const link = await execContainer(id, ["readlink", "/tmp/coder-bin/auggie"]);
    expect(link.stdout.trim()).toBe("/home/coder/.npm-global/bin/auggie");
    const bashrc = await readFileContainer(id, "/home/coder/.bashrc");
    expect(bashrc).toContain("/home/coder/.npm-global/bin");
  });

  test("npm-installs-latest-by-default", async () => {
    const { id, scripts } = await setup({
      skipAuggieMock: true,
      moduleVariables: { install_auggie: "true" },
    });
    await mockNpm(id);
    await runScripts(id, scripts);
    const calls = await readFileContainer(id, "/tmp/npm-calls");
    expect(calls).toMatch(/install -g @augmentcode\/auggie$/m);
  });

  test("npm-failure-is-terminal", async () => {
    const { id, scripts } = await setup({
      skipAuggieMock: true,
      moduleVariables: { install_auggie: "true" },
    });
    await writeExecutable({
      containerId: id,
      filePath: "/usr/local/bin/npm",
      content:
        '#!/bin/bash\nif [ "$1" = "install" ]; then exit 1; fi\necho 11.0.0\n',
    });
    const resp = await runScript(id, "install", scripts.install);
    expect(resp.exitCode).not.toBe(0);
    expect(await installLog(id)).toContain("Auggie CLI installation failed.");
  });

  test("workdir-is-created", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const dir = await execContainer(id, ["test", "-d", projectDir]);
    expect(dir.exitCode).toBe(0);
  });

  test("mcp-and-mcp-files-existing-servers-win", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        mcp: JSON.stringify({
          mcpServers: {
            shared: { command: "module-command" },
            extra: { command: "extra-command", args: ["--flag"] },
          },
        }),
        mcp_files: JSON.stringify([
          "/home/coder/mcp-a.json",
          "/home/coder/missing.json",
        ]),
      },
    });
    await seedFile(
      id,
      "/home/coder/mcp-a.json",
      JSON.stringify({
        mcpServers: {
          fromfile: { type: "http", url: "https://mcp.example.com/mcp" },
          extra: { command: "file-command" },
        },
      }),
    );
    await seedFile(
      id,
      settingsPath,
      JSON.stringify({
        theme: "ansi",
        mcpServers: { shared: { command: "existing-command" } },
      }),
    );
    await runScripts(id, scripts);
    const settings = JSON.parse(await readFileContainer(id, settingsPath));
    expect(settings.theme).toBe("ansi");
    expect(settings.mcpServers.shared.command).toBe("existing-command");
    expect(settings.mcpServers.extra.command).toBe("extra-command");
    expect(settings.mcpServers.fromfile.url).toBe(
      "https://mcp.example.com/mcp",
    );
    expect(settings.mcpServers.coder).toBeUndefined();
    const log = await installLog(id);
    expect(log).toContain(
      "MCP server 'shared' already exists in /home/coder/.augment/settings.json, keeping the existing one.",
    );
    expect(log).toContain("MCP server 'extra' already exists");
    expect(log).toContain("Added MCP server 'fromfile'");
    expect(log).toContain(
      "MCP file /home/coder/missing.json is missing or not valid JSON",
    );
    expect(log).not.toContain("Saved MCP server");
  });

  test("rules-are-written-to-user-rules", async () => {
    const rules = "# Project Guidelines\n\n- Use TypeScript";
    const { id, scripts } = await setup({ moduleVariables: { rules } });
    await runScripts(id, scripts);
    expect((await readFileContainer(id, rulesPath)).trim()).toBe(rules);
  });

  test("stale-rules-are-removed-when-rules-is-empty", async () => {
    const { id, scripts } = await setup();
    await seedFile(id, rulesPath, "# Old rules");
    await runScripts(id, scripts);
    const rules = await execContainer(id, ["test", "-e", rulesPath]);
    expect(rules.exitCode).not.toBe(0);
  });

  test("model-keeps-settings-permissions", async () => {
    const { id, scripts } = await setup({
      moduleVariables: { auggie_model: "sonnet4.5" },
    });
    await seedFile(id, settingsPath, JSON.stringify({ autoUpdate: false }));
    await execContainer(id, ["chmod", "600", settingsPath]);
    await runScripts(id, scripts);
    const mode = await execContainer(id, ["stat", "-c", "%a", settingsPath]);
    expect(mode.stdout.trim()).toBe("600");
    expect(JSON.parse(await readFileContainer(id, settingsPath)).model).toBe(
      "sonnet4.5",
    );
  });

  test("model-is-set-preserving-settings", async () => {
    const { id, scripts } = await setup({
      moduleVariables: { auggie_model: "sonnet4.5" },
    });
    await seedFile(
      id,
      settingsPath,
      JSON.stringify({ model: "gpt5", autoUpdate: false }),
    );
    await runScripts(id, scripts);
    const settings = JSON.parse(await readFileContainer(id, settingsPath));
    expect(settings.model).toBe("sonnet4.5");
    expect(settings.autoUpdate).toBe(false);
  });

  test("jsonc-settings-are-left-unchanged-for-model", async () => {
    const { id, scripts } = await setup({
      moduleVariables: { auggie_model: "sonnet4.5" },
    });
    const jsonc = '{\n  // user comment\n  "theme": "ansi",\n}\n';
    await seedFile(id, settingsPath, jsonc);
    await runScripts(id, scripts);
    expect(await readFileContainer(id, settingsPath)).toBe(jsonc);
    expect(await installLog(id)).toContain(
      "is not a strict JSON object (comments or trailing commas); leaving the model unchanged.",
    );
  });

  test("session-token-uses-coder-env-without-leaking", async () => {
    const secret = "test-access-token-123";
    const { id, coderEnvVars, scripts } = await setup({
      moduleVariables: {
        augment_session_token: JSON.stringify({
          accessToken: secret,
          tenantURL: "https://d1.api.augmentcode.com/",
          scopes: ["read", "write"],
        }),
      },
    });
    expect(coderEnvVars["AUGMENT_SESSION_AUTH"]).toContain(secret);
    expect(scripts.install).not.toContain(secret);
    expect(scripts.install).not.toContain(
      Buffer.from(coderEnvVars["AUGMENT_SESSION_AUTH"]).toString("base64"),
    );
    await runScripts(id, scripts, coderEnvVars);
    expect(await installLog(id)).not.toContain(secret);
  });

  test("pre-post-install-scripts", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        pre_install_script: "#!/bin/bash\necho 'auggie-pre-install-script'",
        post_install_script: "#!/bin/bash\necho 'auggie-post-install-script'",
      },
    });
    await runScripts(id, scripts);
    expect(
      await readFileContainer(id, `${moduleLogDir}/pre_install.log`),
    ).toContain("auggie-pre-install-script");
    expect(
      await readFileContainer(id, `${moduleLogDir}/post_install.log`),
    ).toContain("auggie-post-install-script");
  });
});
