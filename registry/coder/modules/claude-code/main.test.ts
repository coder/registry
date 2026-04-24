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
import { extractCoderEnvVars, writeExecutable } from "../agentapi/test-util";
import path from "path";

// coder-utils orchestrates this module's scripts and can produce multiple
// coder_script resources (pre_install, install, post_install). The shared
// `setup` helper in ../agentapi/test-util.ts assumes a single coder_script
// via findResourceInstance, so we define a local setup helper that collects
// every coder_script in run order.

interface ModuleScripts {
  pre_install?: string;
  install: string;
  post_install?: string;
}

// Script display_names produced by coder-utils (Claude Code prefix + suffix).
// Order matters: scripts run sequentially in this order at agent startup.
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
    const key = `Claude Code: ${suffix}`;
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
  skipClaudeMock?: boolean;
  moduleVariables?: Record<string, string>;
}

const setup = async (
  props?: SetupProps,
): Promise<{
  id: string;
  coderEnvVars: Record<string, string>;
  scripts: ModuleScripts;
}> => {
  const projectDir = "/home/coder/project";
  const moduleDir = path.resolve(import.meta.dir);
  const state = await runTerraformApply(moduleDir, {
    agent_id: "foo",
    workdir: projectDir,
    // Default to skipping the real installer; individual tests opt in.
    install_claude_code: "false",
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
  // Mock `coder` CLI so `coder exp sync` calls from coder-utils wrappers
  // succeed without a real control plane.
  await writeExecutable({
    containerId: id,
    filePath: "/usr/bin/coder",
    content: "#!/bin/bash\nexit 0\n",
  });
  if (!props?.skipClaudeMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/claude",
      content: await Bun.file(
        path.join(moduleDir, "testdata", "claude-mock.sh"),
      ).text(),
    });
  }
  return { id, coderEnvVars, scripts };
};

// Runs the coder-utils script pipeline (pre_install, install, post_install) in
// order inside the container. Each script is written to /tmp and executed
// under bash with the test's env vars exported first.
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
  const ordered: [string, string | undefined][] = [
    ["pre_install", scripts.pre_install],
    ["install", scripts.install],
    ["post_install", scripts.post_install],
  ];
  for (const [name, script] of ordered) {
    if (!script) continue;
    const target = `/tmp/coder-utils-${name}.sh`;
    await writeExecutable({
      containerId: id,
      filePath: target,
      content: script,
    });
    const resp = await execContainer(id, ["bash", "-c", `${envArgs}${target}`]);
    if (resp.exitCode !== 0) {
      console.log(`script ${name} failed:`);
      console.log(resp.stdout);
      console.log(resp.stderr);
      throw new Error(`coder-utils ${name} script exited ${resp.exitCode}`);
    }
  }
};

setDefaultTimeout(60 * 1000);

describe("claude-code", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const installLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder/claude-code/logs/install.log",
    );
    expect(installLog).toContain("Skipping Claude Code installation");
  });

  test("install-claude-code-version", async () => {
    const version = "1.0.40";
    const { id, coderEnvVars, scripts } = await setup({
      skipClaudeMock: true,
      moduleVariables: {
        install_claude_code: "true",
        claude_code_version: version,
      },
    });
    await runScripts(id, scripts, coderEnvVars);
    const installLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder/claude-code/logs/install.log",
    );
    expect(installLog).toContain(version);
  });

  test("anthropic-api-key", async () => {
    const apiKey = "test-api-key-123";
    const { coderEnvVars } = await setup({
      moduleVariables: {
        anthropic_api_key: apiKey,
      },
    });
    expect(coderEnvVars["ANTHROPIC_API_KEY"]).toBe(apiKey);
  });

  test("claude-code-oauth-token", async () => {
    const token = "test-oauth-token-456";
    const { coderEnvVars } = await setup({
      moduleVariables: {
        claude_code_oauth_token: token,
      },
    });
    expect(coderEnvVars["CLAUDE_CODE_OAUTH_TOKEN"]).toBe(token);
  });

  test("claude-mcp-config", async () => {
    const mcpConfig = JSON.stringify({
      mcpServers: {
        test: {
          command: "test-cmd",
          type: "stdio",
        },
      },
    });
    const { id, coderEnvVars, scripts } = await setup({
      skipClaudeMock: true,
      moduleVariables: {
        install_claude_code: "true",
        mcp: mcpConfig,
      },
    });
    await runScripts(id, scripts, coderEnvVars);
    const claudeConfig = await readFileContainer(
      id,
      "/home/coder/.claude.json",
    );
    expect(claudeConfig).toContain("test-cmd");
  });

  test("claude-model", async () => {
    const model = "opus";
    const { coderEnvVars } = await setup({
      moduleVariables: {
        model,
      },
    });
    expect(coderEnvVars["ANTHROPIC_MODEL"]).toBe(model);
  });

  test("pre-post-install-scripts", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        pre_install_script: "#!/bin/bash\necho 'claude-pre-install-script'",
        post_install_script: "#!/bin/bash\necho 'claude-post-install-script'",
      },
    });
    await runScripts(id, scripts);

    const preInstallLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder/claude-code/logs/pre_install.log",
    );
    expect(preInstallLog).toContain("claude-pre-install-script");

    const postInstallLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder/claude-code/logs/post_install.log",
    );
    expect(postInstallLog).toContain("claude-post-install-script");
  });

  test("workdir-variable", async () => {
    const workdir = "/home/coder/claude-test-folder";
    const { id, scripts } = await setup({
      moduleVariables: {
        workdir,
      },
    });
    await runScripts(id, scripts);
    // install.sh echoes ARG_WORKDIR and creates the directory if missing.
    const installLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder/claude-code/logs/install.log",
    );
    expect(installLog).toContain(workdir);
  });

  test("mcp-config-remote-path", async () => {
    const failingUrl = "http://localhost:19999/mcp.json";
    const successUrl =
      "https://raw.githubusercontent.com/coder/coder/main/.mcp.json";

    const { id, coderEnvVars, scripts } = await setup({
      skipClaudeMock: true,
      moduleVariables: {
        install_claude_code: "true",
        mcp_config_remote_path: JSON.stringify([failingUrl, successUrl]),
      },
    });
    await runScripts(id, scripts, coderEnvVars);

    const installLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder/claude-code/logs/install.log",
    );

    // Verify both URLs are attempted.
    expect(installLog).toContain(failingUrl);
    expect(installLog).toContain(successUrl);

    // First URL should fail gracefully.
    expect(installLog).toContain(
      `Warning: Failed to fetch MCP configuration from '${failingUrl}'`,
    );

    // Second URL should succeed.
    expect(installLog).not.toContain(
      `Warning: Failed to fetch MCP configuration from '${successUrl}'`,
    );

    // Should contain the MCP server add command from the successful fetch.
    expect(installLog).toContain(
      "Added stdio MCP server go-language-server to local config",
    );
    expect(installLog).toContain(
      "Added stdio MCP server typescript-language-server to local config",
    );

    // Verify the MCP config was added to .claude.json.
    const claudeConfig = await readFileContainer(
      id,
      "/home/coder/.claude.json",
    );
    expect(claudeConfig).toContain("typescript-language-server");
    expect(claudeConfig).toContain("go-language-server");
  });

  test("standalone-mode-with-api-key", async () => {
    const apiKey = "test-api-key-standalone";
    const workdir = "/home/coder/project";
    const { id, coderEnvVars, scripts } = await setup({
      moduleVariables: {
        anthropic_api_key: apiKey,
      },
    });
    await runScripts(id, scripts, coderEnvVars);

    const installLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder/claude-code/logs/install.log",
    );
    expect(installLog).toContain("Configuring Claude Code for standalone mode");
    expect(installLog).toContain("Standalone mode configured successfully");

    const claudeConfig = await readFileContainer(
      id,
      "/home/coder/.claude.json",
    );
    const parsed = JSON.parse(claudeConfig);
    expect(parsed.primaryApiKey).toBe(apiKey);
    expect(parsed.autoUpdaterStatus).toBe("disabled");
    expect(parsed.hasCompletedOnboarding).toBe(true);
    expect(parsed.bypassPermissionsModeAccepted).toBe(true);
    expect(parsed.hasAcknowledgedCostThreshold).toBe(true);
    expect(parsed.projects[workdir].hasCompletedProjectOnboarding).toBe(true);
    expect(parsed.projects[workdir].hasTrustDialogAccepted).toBe(true);
  });

  test("standalone-mode-with-oauth-token", async () => {
    const token = "test-oauth-token-standalone";
    const { id, coderEnvVars, scripts } = await setup({
      moduleVariables: {
        claude_code_oauth_token: token,
      },
    });
    await runScripts(id, scripts, coderEnvVars);

    const installLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder/claude-code/logs/install.log",
    );
    expect(installLog).toContain("Standalone mode configured successfully");
    expect(installLog).not.toContain("skipping onboarding bypass");

    // Onboarding bypass flags must be present; primaryApiKey is unused when
    // auth happens via CLAUDE_CODE_OAUTH_TOKEN.
    const claudeConfig = await readFileContainer(
      id,
      "/home/coder/.claude.json",
    );
    const parsed = JSON.parse(claudeConfig);
    expect(parsed.hasCompletedOnboarding).toBe(true);
    expect(parsed.bypassPermissionsModeAccepted).toBe(true);
  });

  test("standalone-mode-no-auth", async () => {
    const { id, coderEnvVars, scripts } = await setup();
    await runScripts(id, scripts, coderEnvVars);

    const installLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder/claude-code/logs/install.log",
    );
    expect(installLog).toContain("No authentication configured");
    expect(installLog).toContain("skipping onboarding bypass");

    // .claude.json should not exist when no auth is configured.
    const resp = await execContainer(id, [
      "bash",
      "-c",
      "test -e /home/coder/.claude.json && echo EXISTS || echo ABSENT",
    ]);
    expect(resp.stdout.trim()).toBe("ABSENT");
  });
});
