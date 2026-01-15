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
} from "../agentapi/test-util";
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
  skipClaudeMock?: boolean;
  moduleVariables?: Record<string, string>;
  agentapiMockScript?: string;
}

const setup = async (
  props?: SetupProps,
): Promise<{ id: string; coderEnvVars: Record<string, string> }> => {
  const projectDir = "/home/coder/project";
  const { id, coderEnvVars } = await setupUtil({
    moduleDir: import.meta.dir,
    moduleVariables: {
      install_claude_code: props?.skipClaudeMock ? "true" : "false",
      install_agentapi: props?.skipAgentAPIMock ? "true" : "false",
      workdir: projectDir,
      ...props?.moduleVariables,
    },
    registerCleanup,
    projectDir,
    skipAgentAPIMock: props?.skipAgentAPIMock,
    agentapiMockScript: props?.agentapiMockScript,
  });
  if (!props?.skipClaudeMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/claude",
      content: await loadTestFile(import.meta.dir, "claude-mock.sh"),
    });
  }
  return { id, coderEnvVars };
};

setDefaultTimeout(60 * 1000);

describe("claude-code", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path", async () => {
    const { id } = await setup();
    await execModuleScript(id);
    await expectAgentAPIStarted(id);
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
    await execModuleScript(id, coderEnvVars);
    const resp = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.claude-module/install.log",
    ]);
    expect(resp.stdout).toContain(version_to_install);
  });

  test("check-latest-claude-code-version-works", async () => {
    const { id, coderEnvVars } = await setup({
      skipClaudeMock: true,
      skipAgentAPIMock: true,
      moduleVariables: {
        install_claude_code: "true",
      },
    });
    await execModuleScript(id, coderEnvVars);
    await expectAgentAPIStarted(id);
  });

  test("claude-api-key", async () => {
    const apiKey = "test-api-key-123";
    const { id } = await setup({
      moduleVariables: {
        claude_api_key: apiKey,
      },
    });
    await execModuleScript(id);

    const envCheck = await execContainer(id, [
      "bash",
      "-c",
      'env | grep CLAUDE_API_KEY || echo "CLAUDE_API_KEY not found"',
    ]);
    expect(envCheck.stdout).toContain("CLAUDE_API_KEY");
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
    const { id, coderEnvVars } = await setup({
      skipClaudeMock: true,
      moduleVariables: {
        mcp: mcpConfig,
      },
    });
    await execModuleScript(id, coderEnvVars);

    const resp = await readFileContainer(id, "/home/coder/.claude.json");
    expect(resp).toContain("test-cmd");
  });

  test("claude-task-prompt", async () => {
    const prompt = "This is a task prompt for Claude.";
    const { id } = await setup({
      moduleVariables: {
        ai_prompt: prompt,
      },
    });
    await execModuleScript(id);

    const resp = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.claude-module/agentapi-start.log",
    ]);
    expect(resp.stdout).toContain(prompt);
  });

  test("claude-permission-mode", async () => {
    const mode = "plan";
    const { id } = await setup({
      moduleVariables: {
        permission_mode: mode,
        ai_prompt: "test prompt",
      },
    });
    await execModuleScript(id);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.claude-module/agentapi-start.log",
    ]);
    expect(startLog.stdout).toContain(`--permission-mode ${mode}`);
  });

  test("claude-model", async () => {
    const model = "opus";
    const { coderEnvVars } = await setup({
      moduleVariables: {
        model: model,
        ai_prompt: "test prompt",
      },
    });

    // Verify ANTHROPIC_MODEL env var is set via coder_env
    expect(coderEnvVars["ANTHROPIC_MODEL"]).toBe(model);
  });

  test("claude-continue-resume-task-session", async () => {
    const { id } = await setup({
      moduleVariables: {
        continue: "true",
        report_tasks: "true",
        ai_prompt: "test prompt",
      },
    });

    // Create a mock task session file with the hardcoded task session ID
    // Note: Claude CLI creates files without "session-" prefix when using --session-id
    const taskSessionId = "cd32e253-ca16-4fd3-9825-d837e74ae3c2";
    const sessionDir = `/home/coder/.claude/projects/-home-coder-project`;
    await execContainer(id, ["mkdir", "-p", sessionDir]);
    await execContainer(id, [
      "bash",
      "-c",
      `cat > ${sessionDir}/${taskSessionId}.jsonl << 'SESSIONEOF'
  {"sessionId":"${taskSessionId}","message":{"content":"Task"},"timestamp":"2020-01-01T10:00:00.000Z"}
  {"type":"assistant","message":{"content":"Response"},"timestamp":"2020-01-01T10:00:05.000Z"}
  SESSIONEOF`,
    ]);

    await execModuleScript(id);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.claude-module/agentapi-start.log",
    ]);
    expect(startLog.stdout).toContain("--resume");
    expect(startLog.stdout).toContain(taskSessionId);
    expect(startLog.stdout).toContain("Resuming task session");
    expect(startLog.stdout).toContain("--dangerously-skip-permissions");
  });

  test("pre-post-install-scripts", async () => {
    const { id } = await setup({
      moduleVariables: {
        pre_install_script: "#!/bin/bash\necho 'claude-pre-install-script'",
        post_install_script: "#!/bin/bash\necho 'claude-post-install-script'",
      },
    });
    await execModuleScript(id);

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

  test("workdir-variable", async () => {
    const workdir = "/home/coder/claude-test-folder";
    const { id } = await setup({
      skipClaudeMock: false,
      moduleVariables: {
        workdir,
      },
    });
    await execModuleScript(id);

    const resp = await readFileContainer(
      id,
      "/home/coder/.claude-module/agentapi-start.log",
    );
    expect(resp).toContain(workdir);
  });

  test("coder-mcp-config-created", async () => {
    const { id } = await setup({
      moduleVariables: {
        install_claude_code: "false",
      },
    });
    await execModuleScript(id);

    const installLog = await readFileContainer(
      id,
      "/home/coder/.claude-module/install.log",
    );
    expect(installLog).toContain(
      "Configuring Claude Code to report tasks via Coder MCP",
    );
  });

  test("dangerously-skip-permissions", async () => {
    const { id } = await setup({
      moduleVariables: {
        dangerously_skip_permissions: "true",
      },
    });
    await execModuleScript(id);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.claude-module/agentapi-start.log",
    ]);
    expect(startLog.stdout).toContain(`--dangerously-skip-permissions`);
  });

  test("subdomain-false", async () => {
    const { id } = await setup({
      skipAgentAPIMock: true,
      moduleVariables: {
        subdomain: "false",
        post_install_script: dedent`
          #!/bin/bash
          env | grep AGENTAPI_CHAT_BASE_PATH || echo "AGENTAPI_CHAT_BASE_PATH not found"
          `,
      },
    });

    await execModuleScript(id);
    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.claude-module/post_install.log",
    ]);
    expect(startLog.stdout).toContain(
      "ARG_AGENTAPI_CHAT_BASE_PATH=/@default/default.foo/apps/ccw/chat",
    );
  });

  test("partial-initialization-detection", async () => {
    const { id } = await setup({
      moduleVariables: {
        continue: "true",
        report_tasks: "true",
        ai_prompt: "test prompt",
      },
    });

    const taskSessionId = "cd32e253-ca16-4fd3-9825-d837e74ae3c2";
    const sessionDir = `/home/coder/.claude/projects/-home-coder-project`;
    await execContainer(id, ["mkdir", "-p", sessionDir]);

    await execContainer(id, [
      "bash",
      "-c",
      `echo '{"sessionId":"${taskSessionId}"}' > ${sessionDir}/${taskSessionId}.jsonl`,
    ]);

    await execModuleScript(id);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.claude-module/agentapi-start.log",
    ]);

    // Should start new session, not try to resume invalid one
    expect(startLog.stdout).toContain("Starting new task session");
    expect(startLog.stdout).toContain("--session-id");
  });

  test("standalone-first-build-no-sessions", async () => {
    const { id } = await setup({
      moduleVariables: {
        continue: "true",
        report_tasks: "false",
      },
    });

    await execModuleScript(id);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.claude-module/agentapi-start.log",
    ]);

    // Should start fresh, not try to continue
    expect(startLog.stdout).toContain("No sessions found");
    expect(startLog.stdout).toContain("starting fresh standalone session");
    expect(startLog.stdout).not.toContain("--continue");
  });

  test("standalone-with-sessions-continues", async () => {
    const { id } = await setup({
      moduleVariables: {
        continue: "true",
        report_tasks: "false",
      },
    });

    const sessionDir = `/home/coder/.claude/projects/-home-coder-project`;
    await execContainer(id, ["mkdir", "-p", sessionDir]);
    await execContainer(id, [
      "bash",
      "-c",
      `cat > ${sessionDir}/generic-123.jsonl << 'EOF'
  {"sessionId":"generic-123","message":{"content":"User session"},"timestamp":"2020-01-01T10:00:00.000Z"}
  {"type":"assistant","message":{"content":"Response"},"timestamp":"2020-01-01T10:00:05.000Z"}
  EOF`,
    ]);

    await execModuleScript(id);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.claude-module/agentapi-start.log",
    ]);

    // Should continue existing session
    expect(startLog.stdout).toContain("Sessions found");
    expect(startLog.stdout).toContain(
      "Continuing most recent standalone session",
    );
    expect(startLog.stdout).toContain("--continue");
  });

  test("task-mode-ignores-manual-sessions", async () => {
    const { id } = await setup({
      moduleVariables: {
        continue: "true",
        report_tasks: "true",
        ai_prompt: "test prompt",
      },
    });

    const taskSessionId = "cd32e253-ca16-4fd3-9825-d837e74ae3c2";
    const sessionDir = `/home/coder/.claude/projects/-home-coder-project`;
    await execContainer(id, ["mkdir", "-p", sessionDir]);

    // Create task session (without "session-" prefix, as CLI does)
    await execContainer(id, [
      "bash",
      "-c",
      `cat > ${sessionDir}/${taskSessionId}.jsonl << 'EOF'
  {"sessionId":"${taskSessionId}","message":{"content":"Task"},"timestamp":"2020-01-01T10:00:00.000Z"}
  {"type":"assistant","message":{"content":"Response"},"timestamp":"2020-01-01T10:00:05.000Z"}
  EOF`,
    ]);

    // Create manual session (newer)
    await execContainer(id, [
      "bash",
      "-c",
      `cat > ${sessionDir}/manual-456.jsonl << 'EOF'
  {"sessionId":"manual-456","message":{"content":"Manual"},"timestamp":"2020-01-02T10:00:00.000Z"}
  {"type":"assistant","message":{"content":"Response"},"timestamp":"2020-01-02T10:00:05.000Z"}
  EOF`,
    ]);

    await execModuleScript(id);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.claude-module/agentapi-start.log",
    ]);

    // Should resume task session, not manual session
    expect(startLog.stdout).toContain("Resuming task session");
    expect(startLog.stdout).toContain(taskSessionId);
    expect(startLog.stdout).not.toContain("manual-456");
  });
});
