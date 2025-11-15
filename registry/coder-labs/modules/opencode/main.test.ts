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
  skipOpencodeMock?: boolean;
  moduleVariables?: Record<string, string>;
  agentapiMockScript?: string;
}

const setup = async (props?: SetupProps): Promise<{ id: string }> => {
  const projectDir = "/home/coder/project";
  const { id } = await setupUtil({
    moduleDir: import.meta.dir,
    moduleVariables: {
      install_opencode: props?.skipOpencodeMock ? "true" : "false",
      install_agentapi: props?.skipAgentAPIMock ? "true" : "false",
      workdir: projectDir,
      ...props?.moduleVariables,
    },
    registerCleanup,
    projectDir,
    skipAgentAPIMock: props?.skipAgentAPIMock,
    agentapiMockScript: props?.agentapiMockScript,
  });
  if (!props?.skipOpencodeMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/opencode",
      content: await loadTestFile(import.meta.dir, "opencode-mock.sh"),
    });
  }
  return { id };
};

setDefaultTimeout(60 * 1000);

describe("opencode", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path", async () => {
    const { id } = await setup();
    await execModuleScript(id);
    await expectAgentAPIStarted(id);
  });

  test("install-opencode-version", async () => {
    const version_to_install = "0.1.0";
    const { id } = await setup({
      skipOpencodeMock: true,
      moduleVariables: {
        install_opencode: "true",
        opencode_version: version_to_install,
        pre_install_script: dedent`
          #!/usr/bin/env bash
          set -euo pipefail

          # Mock the opencode install for testing
          mkdir -p /home/coder/.opencode/bin
          echo '#!/bin/bash\necho "opencode mock version ${version_to_install}"' > /home/coder/.opencode/bin/opencode
          chmod +x /home/coder/.opencode/bin/opencode
        `,
      },
    });
    await execModuleScript(id);
    const resp = await execContainer(id, [
      "bash",
      "-c",
      `cat /home/coder/.opencode-module/install.log`,
    ]);
    expect(resp.stdout).toContain(version_to_install);
  });

  test("check-latest-opencode-version-works", async () => {
    const { id } = await setup({
      skipOpencodeMock: true,
      skipAgentAPIMock: true,
      moduleVariables: {
        install_opencode: "true",
        pre_install_script: dedent`
          #!/usr/bin/env bash
          set -euo pipefail

          # Mock the opencode install for testing
          mkdir -p /home/coder/.opencode/bin
          echo '#!/bin/bash\necho "opencode mock latest version"' > /home/coder/.opencode/bin/opencode
          chmod +x /home/coder/.opencode/bin/opencode
        `,
      },
    });
    await execModuleScript(id);
    await expectAgentAPIStarted(id);
  });

  test("opencode-auth-json", async () => {
    const authJson = JSON.stringify({
      token: "test-auth-token-123",
      user: "test-user",
    });
    const { id } = await setup({
      moduleVariables: {
        auth_json: authJson,
      },
    });
    await execModuleScript(id);

    const authFile = await readFileContainer(
      id,
      "/home/coder/.local/share/opencode/auth.json",
    );

    expect(authFile).toContain("test-auth-token-123");
    expect(authFile).toContain("test-user");
  });

  test("opencode-config-json", async () => {
    const configJson = JSON.stringify({
      $schema: "https://opencode.ai/config.json",
      mcp: {
        test: {
          command: ["test-cmd"],
          type: "local",
        },
      },
      model: "anthropic/claude-sonnet-4-20250514",
    });
    const { id } = await setup({
      moduleVariables: {
        config_json: configJson,
      },
    });
    await execModuleScript(id);

    const configFile = await readFileContainer(
      id,
      "/home/coder/.config/opencode/opencode.json",
    );
    expect(configFile).toContain("test-cmd");
    expect(configFile).toContain("anthropic/claude-sonnet-4-20250514");
  });

  test("opencode-ai-prompt", async () => {
    const prompt = "This is a task prompt for OpenCode.";
    const { id } = await setup({
      moduleVariables: {
        ai_prompt: prompt,
      },
    });
    await execModuleScript(id);

    const resp = await execContainer(id, [
      "bash",
      "-c",
      `cat /home/coder/.opencode-module/agentapi-start.log`,
    ]);
    expect(resp.stdout).toContain(prompt);
  });

  test("opencode-continue-flag", async () => {
    const { id } = await setup({
      moduleVariables: {
        continue: "true",
        ai_prompt: "test prompt",
      },
    });
    await execModuleScript(id);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.opencode-module/agentapi-start.log",
    ]);
    expect(startLog.stdout).toContain("--continue");
  });

  test("opencode-continue-with-session-id", async () => {
    const sessionId = "session-123";
    const { id } = await setup({
      moduleVariables: {
        continue: "true",
        session_id: sessionId,
        ai_prompt: "test prompt",
      },
    });
    await execModuleScript(id);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.opencode-module/agentapi-start.log",
    ]);
    expect(startLog.stdout).toContain("--continue");
    expect(startLog.stdout).toContain(`--session ${sessionId}`);
  });

  test("opencode-session-id", async () => {
    const sessionId = "session-123";
    const { id } = await setup({
      moduleVariables: {
        session_id: sessionId,
        ai_prompt: "test prompt",
      },
    });
    await execModuleScript(id);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.opencode-module/agentapi-start.log",
    ]);
    expect(startLog.stdout).toContain(`--session ${sessionId}`);
  });

  test("opencode-report-tasks-enabled", async () => {
    const { id } = await setup({
      moduleVariables: {
        report_tasks: "true",
        ai_prompt: "test prompt",
      },
    });
    await execModuleScript(id);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.opencode-module/agentapi-start.log",
    ]);
    expect(startLog.stdout).toContain(
      "report your progress using coder_report_task",
    );
  });

  test("opencode-report-tasks-disabled", async () => {
    const { id } = await setup({
      moduleVariables: {
        report_tasks: "false",
        ai_prompt: "test prompt",
      },
    });
    await execModuleScript(id);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.opencode-module/agentapi-start.log",
    ]);
    expect(startLog.stdout).not.toContain(
      "report your progress using coder_report_task",
    );
  });

  test("cli-app-creation", async () => {
    const { id } = await setup({
      moduleVariables: {
        cli_app: "true",
        cli_app_display_name: "OpenCode Terminal",
      },
    });
    await execModuleScript(id);
    // CLI app creation is handled by the agentapi module
    // We just verify the setup completed successfully
    await expectAgentAPIStarted(id);
  });

  test("pre-post-install-scripts", async () => {
    const { id } = await setup({
      moduleVariables: {
        pre_install_script: "#!/bin/bash\necho 'opencode-pre-install-script'",
        post_install_script: "#!/bin/bash\necho 'opencode-post-install-script'",
      },
    });
    await execModuleScript(id);

    const preInstallLog = await readFileContainer(
      id,
      "/home/coder/.opencode-module/pre_install.log",
    );
    expect(preInstallLog).toContain("opencode-pre-install-script");

    const postInstallLog = await readFileContainer(
      id,
      "/home/coder/.opencode-module/post_install.log",
    );
    expect(postInstallLog).toContain("opencode-post-install-script");
  });

  test("workdir-variable", async () => {
    const workdir = "/home/coder/opencode-test-folder";
    const { id } = await setup({
      skipOpencodeMock: false,
      moduleVariables: {
        workdir,
      },
    });
    await execModuleScript(id);

    const resp = await readFileContainer(
      id,
      "/home/coder/.opencode-module/agentapi-start.log",
    );
    expect(resp).toContain(workdir);
  });

  test("subdomain-enabled", async () => {
    const { id } = await setup({
      moduleVariables: {
        subdomain: "true",
      },
    });
    await execModuleScript(id);
    // Subdomain configuration is handled by the agentapi module
    // We just verify the setup completed successfully
    await expectAgentAPIStarted(id);
  });

  test("custom-display-names", async () => {
    const { id } = await setup({
      moduleVariables: {
        web_app_display_name: "Custom OpenCode Web",
        cli_app_display_name: "Custom OpenCode CLI",
        cli_app: "true",
      },
    });
    await execModuleScript(id);
    // Display names are handled by the agentapi module
    // We just verify the setup completed successfully
    await expectAgentAPIStarted(id);
  });
});
