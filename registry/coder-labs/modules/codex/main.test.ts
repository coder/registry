import {
  test,
  afterEach,
  describe,
  setDefaultTimeout,
  beforeAll,
  expect,
} from "bun:test";
import { execContainer, readFileContainer, runTerraformInit } from "~test";
import {
  loadTestFile,
  writeExecutable,
  setup as setupUtil,
  execModuleScript,
  expectAgentAPIStarted,
} from "../../../coder/modules/agentapi/test-util";
import dedent from "dedent";

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
  skipAgentAPIMock?: boolean;
  skipCodexMock?: boolean;
  moduleVariables?: Record<string, string>;
  agentapiMockScript?: string;
}

const setup = async (props?: SetupProps): Promise<{ id: string }> => {
  const projectDir = "/home/coder/project";

  const moduleVars: Record<string, string> = {
    install_codex: props?.skipCodexMock ? "true" : "false",
    codex_model: "gpt-4-turbo",
    workdir: "/home/coder",
    ...props?.moduleVariables,
  };

  // For backward compatibility: install_agentapi takes precedence over enable_tasks
  // Only set install_agentapi when explicitly installing real AgentAPI
  if (props?.skipAgentAPIMock) {
    moduleVars.install_agentapi = "true";
  }
  // Otherwise, let enable_tasks control whether agentapi module runs
  // (defaults to true unless explicitly disabled in moduleVariables)

  const { id } = await setupUtil({
    moduleDir: import.meta.dir,
    moduleVariables: moduleVars,
    registerCleanup,
    projectDir,
    skipAgentAPIMock: props?.skipAgentAPIMock,
    agentapiMockScript: props?.agentapiMockScript,
  });
  if (!props?.skipCodexMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/codex",
      content: await loadTestFile(import.meta.dir, "codex-mock.sh"),
    });
  }
  return { id };
};

setDefaultTimeout(60 * 1000);

describe("codex", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path", async () => {
    const { id } = await setup();
    await execModuleScript(id);
    await expectAgentAPIStarted(id);
  });

  test("install-codex-version", async () => {
    const version_to_install = "0.10.0";
    const { id } = await setup({
      skipCodexMock: true,
      moduleVariables: {
        install_codex: "true",
        codex_version: version_to_install,
      },
    });
    await execModuleScript(id);
    const resp = await execContainer(id, [
      "bash",
      "-c",
      `cat /home/coder/.codex-module/install.log`,
    ]);
    expect(resp.stdout).toContain(version_to_install);
  });

  test("check-latest-codex-version-works", async () => {
    const { id } = await setup({
      skipCodexMock: true,
      skipAgentAPIMock: true,
      moduleVariables: {
        install_codex: "true",
      },
    });
    await execModuleScript(id);
    await expectAgentAPIStarted(id);
  });

  test("base-config-toml", async () => {
    const baseConfig = dedent`
      sandbox_mode = "danger-full-access"
      approval_policy = "never"
      preferred_auth_method = "apikey"

      [custom_section]
      new_feature = true
    `.trim();
    const { id } = await setup({
      moduleVariables: {
        base_config_toml: baseConfig,
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(id, "/home/coder/.codex/config.toml");
    expect(resp).toContain('sandbox_mode = "danger-full-access"');
    expect(resp).toContain('preferred_auth_method = "apikey"');
    expect(resp).toContain("[custom_section]");
    expect(resp).toContain("[mcp_servers.Coder]");
  });

  test("codex-api-key", async () => {
    const apiKey = "test-api-key-123";
    const { id } = await setup({
      moduleVariables: {
        openai_api_key: apiKey,
      },
    });
    await execModuleScript(id);

    const resp = await readFileContainer(
      id,
      "/home/coder/.codex-module/agentapi-start.log",
    );
    expect(resp).toContain("OpenAI API Key: Provided");
  });

  test("pre-post-install-scripts", async () => {
    const { id } = await setup({
      moduleVariables: {
        pre_install_script: "#!/bin/bash\necho 'pre-install-script'",
        post_install_script: "#!/bin/bash\necho 'post-install-script'",
      },
    });
    await execModuleScript(id);
    const preInstallLog = await readFileContainer(
      id,
      "/home/coder/.codex-module/pre_install.log",
    );
    expect(preInstallLog).toContain("pre-install-script");
    const postInstallLog = await readFileContainer(
      id,
      "/home/coder/.codex-module/post_install.log",
    );
    expect(postInstallLog).toContain("post-install-script");
  });

  test("workdir-variable", async () => {
    const workdir = "/tmp/codex-test-workdir";
    const { id } = await setup({
      skipCodexMock: false,
      moduleVariables: {
        workdir,
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(
      id,
      "/home/coder/.codex-module/install.log",
    );
    expect(resp).toContain(workdir);
  });

  test("additional-mcp-servers", async () => {
    const additional = dedent`
      [mcp_servers.GitHub]
      command = "npx"
      args = ["-y", "@modelcontextprotocol/server-github"]
      type = "stdio"
      description = "GitHub integration"

      [mcp_servers.FileSystem]
      command = "npx"
      args = ["-y", "@modelcontextprotocol/server-filesystem", "/workspace"]
      type = "stdio"
      description = "File system access"
    `.trim();
    const { id } = await setup({
      moduleVariables: {
        additional_mcp_servers: additional,
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(id, "/home/coder/.codex/config.toml");
    expect(resp).toContain("[mcp_servers.GitHub]");
    expect(resp).toContain("[mcp_servers.FileSystem]");
    expect(resp).toContain("[mcp_servers.Coder]");
    expect(resp).toContain("GitHub integration");
  });

  test("full-custom-config", async () => {
    const baseConfig = dedent`
      sandbox_mode = "read-only"
      approval_policy = "untrusted"
      preferred_auth_method = "chatgpt"
      custom_setting = "test-value"

      [advanced_settings]
      timeout = 30000
      debug = true
      logging_level = "verbose"
    `.trim();

    const additionalMCP = dedent`
      [mcp_servers.CustomTool]
      command = "/usr/local/bin/custom-tool"
      args = ["--serve", "--port", "8080"]
      type = "stdio"
      description = "Custom development tool"

      [mcp_servers.DatabaseMCP]
      command = "python"
      args = ["-m", "database_mcp_server"]
      type = "stdio"
      description = "Database query interface"
    `.trim();

    const { id } = await setup({
      moduleVariables: {
        base_config_toml: baseConfig,
        additional_mcp_servers: additionalMCP,
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(id, "/home/coder/.codex/config.toml");

    // Check base config
    expect(resp).toContain('sandbox_mode = "read-only"');
    expect(resp).toContain('preferred_auth_method = "chatgpt"');
    expect(resp).toContain('custom_setting = "test-value"');
    expect(resp).toContain("[advanced_settings]");
    expect(resp).toContain('logging_level = "verbose"');

    // Check MCP servers
    expect(resp).toContain("[mcp_servers.Coder]");
    expect(resp).toContain("[mcp_servers.CustomTool]");
    expect(resp).toContain("[mcp_servers.DatabaseMCP]");
    expect(resp).toContain("Custom development tool");
    expect(resp).toContain("Database query interface");
  });

  test("minimal-default-config", async () => {
    const { id } = await setup({
      moduleVariables: {
        // No base_config_toml or additional_mcp_servers - should use defaults
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(id, "/home/coder/.codex/config.toml");

    // Check default base config
    expect(resp).toContain('sandbox_mode = "workspace-write"');
    expect(resp).toContain('approval_policy = "never"');
    expect(resp).toContain("[sandbox_workspace_write]");
    expect(resp).toContain("network_access = true");

    // Check only Coder MCP server is present
    expect(resp).toContain("[mcp_servers.Coder]");
    expect(resp).toContain("Report ALL tasks and statuses");

    // Ensure no additional MCP servers
    const mcpServerCount = (resp.match(/\[mcp_servers\./g) || []).length;
    expect(mcpServerCount).toBe(1);
  });

  test("codex-system-prompt", async () => {
    const prompt = "This is a system prompt for Codex.";
    const { id } = await setup({
      moduleVariables: {
        codex_system_prompt: prompt,
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(id, "/home/coder/.codex/AGENTS.md");
    expect(resp).toContain(prompt);
  });

  test("codex-system-prompt-skip-append-if-exists", async () => {
    const prompt_1 = "This is a system prompt for Codex.";
    const prompt_2 = "This is a system prompt for Goose.";
    const prompt_3 = dedent`
    This is a system prompt for Codex.
    This is a system prompt for Gemini.
    `.trim();
    const pre_install_script = dedent`
        #!/bin/bash
        mkdir -p /home/coder/.codex
        echo -e "${prompt_3}" >> /home/coder/.codex/AGENTS.md
        `.trim();

    const { id } = await setup({
      moduleVariables: {
        pre_install_script,
        codex_system_prompt: prompt_2,
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(id, "/home/coder/.codex/AGENTS.md");
    expect(resp).toContain(prompt_1);
    expect(resp).toContain(prompt_2);

    // Re-run with a prompt that already exists, it should not append again
    const { id: id_2 } = await setup({
      moduleVariables: {
        pre_install_script,
        codex_system_prompt: prompt_1,
      },
    });
    await execModuleScript(id_2);
    const resp_2 = await readFileContainer(
      id_2,
      "/home/coder/.codex/AGENTS.md",
    );
    expect(resp_2).toContain(prompt_1);
    const count = (resp_2.match(new RegExp(prompt_1, "g")) || []).length;
    expect(count).toBe(1);
  });

  test("codex-ai-task-prompt", async () => {
    const prompt = "This is a system prompt for Codex.";
    const { id } = await setup({
      moduleVariables: {
        ai_prompt: prompt,
      },
    });
    await execModuleScript(id);
    const resp = await execContainer(id, [
      "bash",
      "-c",
      `cat /home/coder/.codex-module/agentapi-start.log`,
    ]);
    expect(resp.stdout).toContain(prompt);
  });

  test("start-without-prompt", async () => {
    const { id } = await setup({
      moduleVariables: {
        codex_system_prompt: "", // Explicitly disable system prompt
      },
    });
    await execModuleScript(id);
    const prompt = await execContainer(id, [
      "ls",
      "-l",
      "/home/coder/.codex/AGENTS.md",
    ]);
    expect(prompt.exitCode).not.toBe(0);
    expect(prompt.stderr).toContain("No such file or directory");
  });

  test("codex-continue-capture-new-session", async () => {
    const { id } = await setup({
      moduleVariables: {
        continue: "true",
        ai_prompt: "test task",
      },
    });

    const workdir = "/home/coder";
    const expectedSessionId = "019a1234-5678-9abc-def0-123456789012";
    const sessionsDir = "/home/coder/.codex/sessions";
    const sessionFile = `${sessionsDir}/${expectedSessionId}.jsonl`;

    await execContainer(id, ["mkdir", "-p", sessionsDir]);
    await execContainer(id, [
      "bash",
      "-c",
      `echo '{"id":"${expectedSessionId}","cwd":"${workdir}","created":"2024-10-24T20:00:00Z","model":"gpt-4-turbo"}' > ${sessionFile}`,
    ]);

    await execModuleScript(id);

    await expectAgentAPIStarted(id);

    const trackingFile = "/home/coder/.codex-module/.codex-task-session";
    const maxAttempts = 30;
    let trackingFileContents = "";
    for (let attempt = 0; attempt < maxAttempts; attempt++) {
      const result = await execContainer(id, [
        "bash",
        "-c",
        `cat ${trackingFile} 2>/dev/null || echo ""`,
      ]);
      if (result.stdout.trim().length > 0) {
        trackingFileContents = result.stdout;
        break;
      }
      await new Promise((resolve) => setTimeout(resolve, 500));
    }

    expect(trackingFileContents).toContain(`${workdir}|${expectedSessionId}`);

    const startLog = await readFileContainer(
      id,
      "/home/coder/.codex-module/agentapi-start.log",
    );
    expect(startLog).toContain("Capturing new session ID");
    expect(startLog).toContain("Session tracked");
    expect(startLog).toContain(expectedSessionId);
  });

  test("codex-continue-resume-existing-session", async () => {
    const { id } = await setup({
      moduleVariables: {
        continue: "true",
        ai_prompt: "test prompt",
      },
    });

    const workdir = "/home/coder";
    const mockSessionId = "019a1234-5678-9abc-def0-123456789012";
    const trackingFile = "/home/coder/.codex-module/.codex-task-session";

    await execContainer(id, ["mkdir", "-p", "/home/coder/.codex-module"]);
    await execContainer(id, [
      "bash",
      "-c",
      `echo "${workdir}|${mockSessionId}" > ${trackingFile}`,
    ]);

    await execModuleScript(id);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.codex-module/agentapi-start.log",
    ]);
    expect(startLog.stdout).toContain("Found existing task session");
    expect(startLog.stdout).toContain(mockSessionId);
    expect(startLog.stdout).toContain("Resuming existing session");
    expect(startLog.stdout).toContain(
      `Starting Codex with arguments: --model gpt-4-turbo resume ${mockSessionId}`,
    );
    expect(startLog.stdout).not.toContain("test prompt");
  });

  test("codex-with-aibridge", async () => {
    const { id } = await setup({
      moduleVariables: {
        enable_aibridge: "true",
        model_reasoning_effort: "none",
      },
    });

    await execModuleScript(id);

    const startLog = await readFileContainer(
      id,
      "/home/coder/.codex-module/agentapi-start.log",
    );

    const configToml = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    expect(startLog).toContain("AI Bridge is enabled, using profile aibridge");
    expect(startLog).toContain(
      "Starting Codex with arguments: --profile aibridge",
    );
    expect(configToml).toContain(
      "[profiles.aibridge]\n" + 'model_provider = "aibridge"',
    );
    // Verify profile = "aibridge" is set at the top of the config
    expect(configToml.startsWith('profile = "aibridge"')).toBe(true);
  });

  test("codex-standalone-mode", async () => {
    // Test standalone mode without tasks (enable_tasks = false)
    // workdir should default to /home/coder when not explicitly provided
    const { id } = await setup({
      moduleVariables: {
        enable_tasks: "false",
        enable_aibridge: "true",
      },
    });

    await execModuleScript(id);

    const configToml = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    // In standalone mode, config should still have aibridge profile set as default
    expect(configToml.startsWith('profile = "aibridge"')).toBe(true);
    expect(configToml).toContain("[profiles.aibridge]");
  });
});
