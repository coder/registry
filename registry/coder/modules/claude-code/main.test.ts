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

const setup = async (props?: SetupProps): Promise<{ id: string }> => {
  const projectDir = "/home/coder/project";
  const { id } = await setupUtil({
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
  return { id };
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
    const { id } = await setup({
      skipClaudeMock: true,
      moduleVariables: {
        install_claude_code: "true",
        claude_code_version: version_to_install,
      },
    });
    await execModuleScript(id);
    const resp = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.claude-module/install.log",
    ]);
    expect(resp.stdout).toContain(version_to_install);
  });

  test("check-latest-claude-code-version-works", async () => {
    const { id } = await setup({
      skipClaudeMock: true,
      skipAgentAPIMock: true,
      moduleVariables: {
        install_claude_code: "true",
      },
    });
    await execModuleScript(id);
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
    const { id } = await setup({
      skipClaudeMock: true,
      moduleVariables: {
        mcp: mcpConfig,
      },
    });
    await execModuleScript(id);

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
        task_prompt: "test prompt",
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
    const { id } = await setup({
      moduleVariables: {
        model: model,
        task_prompt: "test prompt",
      },
    });
    await execModuleScript(id);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.claude-module/agentapi-start.log",
    ]);
    expect(startLog.stdout).toContain(`--model ${model}`);
  });

  test("claude-continue-previous-conversation", async () => {
    const { id } = await setup({
      moduleVariables: {
        continue: "true",
        task_prompt: "test prompt",
      },
    });
    await execModuleScript(id);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.claude-module/agentapi-start.log",
    ]);
    expect(startLog.stdout).toContain("--continue");
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
});
