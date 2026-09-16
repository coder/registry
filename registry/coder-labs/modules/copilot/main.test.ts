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
    const key = `Copilot: ${suffix}`;
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
  skipCopilotMock?: boolean;
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
    install_copilot: "false",
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

  await execContainer(id, ["bash", "-c", `mkdir -p '${projectDir}'`]);
  await writeExecutable({
    containerId: id,
    filePath: "/usr/bin/coder",
    content: "#!/bin/bash\nexit 0\n",
  });
  if (!props?.skipCopilotMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/copilot",
      content: await Bun.file(
        path.join(moduleDir, "testdata", "copilot-mock.sh"),
      ).text(),
    });
  }
  return { id, coderEnvVars, scripts };
};

const runScripts = async (
  id: string,
  scripts: ModuleScripts,
  env?: Record<string, string>,
) => {
  const entries = env ? Object.entries(env) : [];
  const envArgs =
    entries.length > 0
      ? entries
          .map(
            ([key, value]) => `export ${key}="${value.replace(/"/g, '\\"')}"`,
          )
          .join(" && ") + " && "
      : "";
  const runRenderedScript = async (name: string, script: string) => {
    const target = `/tmp/coder-utils-${name}.sh`;
    await writeExecutable({
      containerId: id,
      filePath: target,
      content: script,
    });
    return execContainer(id, ["bash", "-c", `${envArgs}${target}`]);
  };
  const ordered: [string, string | undefined][] = [
    ["pre_install", scripts.pre_install],
    ["install", scripts.install],
    ["post_install", scripts.post_install],
  ];
  for (const [name, script] of ordered) {
    if (!script) continue;
    const resp = await runRenderedScript(name, script);
    if (resp.exitCode !== 0) {
      console.log(`script ${name} failed:`);
      console.log(resp.stdout);
      console.log(resp.stderr);
      throw new Error(`coder-utils ${name} script exited ${resp.exitCode}`);
    }
  }
};

const configDir = "/home/coder/.copilot";
const readConfig = (id: string) =>
  readFileContainer(id, `${configDir}/config.json`);
const readMcpConfig = (id: string) =>
  readFileContainer(id, `${configDir}/mcp-config.json`);
const installLog = (id: string) =>
  readFileContainer(
    id,
    "/home/coder/.coder-modules/coder-labs/copilot/logs/install.log",
  );

setDefaultTimeout(60 * 1000);

describe("copilot", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path-skips-install-when-present", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const log = await installLog(id);
    expect(log).toContain("Validated existing GitHub Copilot CLI");
    expect(log).toContain("Copilot module setup completed.");
  });

  test("writes-config-without-mcp-servers", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const config = JSON.parse(await readConfig(id));
    expect(config.banner).toBe("never");
    expect(config.theme).toBe("auto");
    expect(config.trusted_folders).toContain(projectDir);
    // mcpServers must never be written into config.json.
    expect(config.mcpServers).toBeUndefined();
  });

  test("merges-trusted-directories", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        trusted_directories: JSON.stringify(["/workspace", "/data"]),
      },
    });
    await runScripts(id, scripts);
    const config = JSON.parse(await readConfig(id));
    expect(config.trusted_folders).toContain(projectDir);
    expect(config.trusted_folders).toContain("/workspace");
    expect(config.trusted_folders).toContain("/data");
  });

  test("writes-custom-mcp-servers-without-coder-server", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        mcp_config: JSON.stringify({
          mcpServers: {
            filesystem: {
              command: "npx",
              args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
              type: "local",
              tools: ["*"],
            },
          },
        }),
      },
    });
    await runScripts(id, scripts);
    const mcp = JSON.parse(await readMcpConfig(id));
    // The server is written straight into ~/.copilot/mcp-config.json.
    expect(mcp.mcpServers.filesystem).toBeDefined();
    expect(mcp.mcpServers.filesystem.command).toBe("npx");
    // The task-reporting "coder" MCP server must not be injected anymore.
    expect(mcp.mcpServers.coder).toBeUndefined();
  });

  test("github-token-env-vars", async () => {
    const token = "ghp_test_token_123";
    const { coderEnvVars } = await setup({
      moduleVariables: {
        github_token: token,
      },
    });
    expect(coderEnvVars["GITHUB_TOKEN"]).toBe(token);
    expect(coderEnvVars["GH_TOKEN"]).toBe(token);
  });
});
