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
  runTerraformApply,
  runTerraformInit,
  runContainer,
  removeContainer,
  type TerraformState,
} from "~test";
import {
  loadTestFile,
  writeExecutable,
  extractCoderEnvVars,
} from "../agentapi/test-util";

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

// Order scripts in the same sequence coder-utils enforces at runtime via
// `coder exp sync`: pre_install -> install -> post_install.
const SCRIPT_ORDER = [
  "Pre-Install Script",
  "Install Script",
  "Post-Install Script",
];

const collectScripts = (state: TerraformState): string[] => {
  const scripts: { displayName: string; script: string }[] = [];
  for (const resource of state.resources) {
    if (resource.type !== "coder_script") continue;
    for (const instance of resource.instances) {
      const attrs = instance.attributes as Record<string, unknown>;
      scripts.push({
        displayName: String(attrs.display_name ?? ""),
        script: String(attrs.script ?? ""),
      });
    }
  }
  scripts.sort(
    (a, b) =>
      SCRIPT_ORDER.indexOf(a.displayName) - SCRIPT_ORDER.indexOf(b.displayName),
  );
  return scripts.map((s) => s.script);
};

const setup = async (
  props?: SetupProps,
): Promise<{ id: string; coderEnvVars: Record<string, string> }> => {
  const moduleVariables: Record<string, string> = {
    agent_id: "foo",
    install_claude_code: props?.skipClaudeMock ? "true" : "false",
    ...props?.moduleVariables,
  };
  const state = await runTerraformApply(import.meta.dir, moduleVariables);
  const scripts = collectScripts(state);
  const coderEnvVars = extractCoderEnvVars(state);

  const id = await runContainer("codercom/enterprise-node:latest");
  registerCleanup(async () => {
    if (
      process.env["DEBUG"] === "true" ||
      process.env["DEBUG"] === "1" ||
      process.env["DEBUG"] === "yes"
    ) {
      console.log(`Not removing container ${id} in debug mode`);
      console.log(`Run "docker rm -f ${id}" to remove it manually.`);
    } else {
      await removeContainer(id);
    }
  });

  // `coder-utils` wraps each script with `coder exp sync` calls. Install a
  // no-op mock so the script runs in the minimal test container.
  await writeExecutable({
    containerId: id,
    filePath: "/usr/bin/coder",
    content: await loadTestFile(import.meta.dir, "coder-mock.sh"),
  });

  if (!props?.skipClaudeMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/claude",
      content: await loadTestFile(import.meta.dir, "claude-mock.sh"),
    });
  }

  // Concatenate scripts in dependency order into a single driver. Each script
  // runs in its own subshell so that `set -e` and `exit` stay contained.
  const driver = scripts
    .map((s, i) => `(\n# --- script ${i} ---\n${s}\n)`)
    .join("\n");
  await writeExecutable({
    containerId: id,
    filePath: "/home/coder/script.sh",
    content: driver,
  });

  return { id, coderEnvVars };
};

const runModuleScripts = async (id: string, env?: Record<string, string>) => {
  const envArgs = env
    ? Object.entries(env)
        .map(([key, value]) => `export ${key}="${value.replace(/"/g, '\\"')}"`)
        .join(" && ") + " && "
    : "";
  const resp = await execContainer(id, [
    "bash",
    "-c",
    `${envArgs}set -o errexit; set -o pipefail; cd /home/coder && ./script.sh 2>&1 | tee /home/coder/script.log`,
  ]);
  if (resp.exitCode !== 0) {
    console.log(resp.stdout);
    console.log(resp.stderr);
  }
  return resp;
};

setDefaultTimeout(60 * 1000);

describe("claude-code", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path", async () => {
    const { id } = await setup();
    await runModuleScripts(id);
    const installLog = await readFileContainer(
      id,
      "/home/coder/.claude-module/install.log",
    );
    expect(installLog).toContain("ARG_INSTALL_CLAUDE_CODE");
  });

  test("install-claude-code-version", async () => {
    const version_to_install = "1.0.40";
    const { id, coderEnvVars } = await setup({
      skipClaudeMock: true,
      moduleVariables: {
        install_claude_code: "true",
        claude_code_version: version_to_install,
      },
    });
    await runModuleScripts(id, coderEnvVars);
    const resp = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.claude-module/install.log",
    ]);
    expect(resp.stdout).toContain(version_to_install);
  });

  test("install-claude-code-latest", async () => {
    const { id, coderEnvVars } = await setup({
      skipClaudeMock: true,
      moduleVariables: {
        install_claude_code: "true",
      },
    });
    await runModuleScripts(id, coderEnvVars);
    const resp = await execContainer(id, [
      "bash",
      "-c",
      'export PATH="$HOME/.local/bin:$PATH" && claude --version',
    ]);
    expect(resp.exitCode).toBe(0);
    expect(resp.stdout).toMatch(/\d+\.\d+\.\d+/);
  });

  test("anthropic-api-key", async () => {
    const apiKey = "sk-test-api-key-123";
    const { id, coderEnvVars } = await setup({
      moduleVariables: {
        anthropic_api_key: apiKey,
      },
    });
    expect(coderEnvVars["ANTHROPIC_API_KEY"]).toBe(apiKey);
    expect(coderEnvVars["CLAUDE_API_KEY"]).toBeUndefined();
    await runModuleScripts(id);
  });

  test("claude-oauth-token", async () => {
    const token = "oauth-live-token";
    const { coderEnvVars } = await setup({
      moduleVariables: {
        claude_code_oauth_token: token,
      },
    });
    expect(coderEnvVars["CLAUDE_CODE_OAUTH_TOKEN"]).toBe(token);
  });

  test("aibridge-env-vars", async () => {
    // In the test env data.coder_workspace_owner.me.session_token is empty,
    // so ANTHROPIC_AUTH_TOKEN is emitted with an empty value (filtered out by
    // extractCoderEnvVars). Verify ANTHROPIC_BASE_URL and confirm
    // ANTHROPIC_API_KEY is absent.
    const { coderEnvVars } = await setup({
      moduleVariables: {
        enable_aibridge: "true",
      },
    });
    expect(coderEnvVars["ANTHROPIC_BASE_URL"]).toContain(
      "/api/v2/aibridge/anthropic",
    );
    expect(coderEnvVars["ANTHROPIC_API_KEY"]).toBeUndefined();
  });

  test("claude-model", async () => {
    const model = "opus";
    const { coderEnvVars } = await setup({
      moduleVariables: {
        model: model,
      },
    });
    expect(coderEnvVars["ANTHROPIC_MODEL"]).toBe(model);
  });

  test("claude-mcp-inline-user-scope", async () => {
    const mcpConfig = JSON.stringify({
      mcpServers: {
        "test-server": {
          command: "test-cmd",
          args: ["--config", "test.json"],
        },
      },
    });
    const { id } = await setup({
      moduleVariables: {
        mcp: mcpConfig,
      },
    });
    await runModuleScripts(id);

    const installLog = await readFileContainer(
      id,
      "/home/coder/.claude-module/install.log",
    );
    expect(installLog).toContain("claude mcp add-json --scope user");
    expect(installLog).toContain("test-server");
  });

  test("claude-mcp-remote-user-scope", async () => {
    const failingUrl = "http://localhost:19999/mcp.json";
    const successUrl =
      "https://raw.githubusercontent.com/coder/coder/main/.mcp.json";

    const { id, coderEnvVars } = await setup({
      skipClaudeMock: true,
      moduleVariables: {
        mcp_config_remote_path: JSON.stringify([failingUrl, successUrl]),
      },
    });
    await runModuleScripts(id, coderEnvVars);

    const installLog = await readFileContainer(
      id,
      "/home/coder/.claude-module/install.log",
    );

    expect(installLog).toContain(failingUrl);
    expect(installLog).toContain(successUrl);
    expect(installLog).toContain(
      `Warning: Failed to fetch MCP configuration from '${failingUrl}'`,
    );
    expect(installLog).not.toContain(
      `Warning: Failed to fetch MCP configuration from '${successUrl}'`,
    );
    expect(installLog).toContain("claude mcp add-json --scope user");
  });

  test("pre-post-install-scripts", async () => {
    const { id } = await setup({
      moduleVariables: {
        pre_install_script: "#!/bin/bash\necho 'claude-pre-install-script'",
        post_install_script: "#!/bin/bash\necho 'claude-post-install-script'",
      },
    });
    await runModuleScripts(id);

    const preInstallLog = await readFileContainer(
      id,
      "/home/coder/.claude-module/pre_install.log",
    );
    expect(preInstallLog).toContain("claude-pre-install-script");

    const postInstallLog = await readFileContainer(
      id,
      "/home/coder/.claude-module/post_install.log",
    );
    expect(postInstallLog).toContain("claude-post-install-script");
  });
});
