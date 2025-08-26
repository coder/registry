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
  skipAuggieMock?: boolean;
  moduleVariables?: Record<string, string>;
  agentapiMockScript?: string;
}

const setup = async (props?: SetupProps): Promise<{ id: string }> => {
  const projectDir = "/home/coder/project";
  const { id } = await setupUtil({
    moduleDir: import.meta.dir,
    moduleVariables: {
      install_auggie: props?.skipAuggieMock ? "true" : "false",
      install_agentapi: props?.skipAgentAPIMock ? "true" : "false",
      folder: projectDir,
      ...props?.moduleVariables,
    },
    registerCleanup,
    projectDir,
    skipAgentAPIMock: props?.skipAgentAPIMock,
    agentapiMockScript: props?.agentapiMockScript,
  });
  if (!props?.skipAuggieMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/auggie",
      content: await loadTestFile(import.meta.dir, "auggie-mock.sh"),
    });
  }
  return { id };
};

setDefaultTimeout(60 * 1000);

describe("auggie", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path", async () => {
    const { id } = await setup();
    await execModuleScript(id);
    await expectAgentAPIStarted(id);
  });

  test("install-auggie-version", async () => {
    const version_to_install = "0.3.0";
    const { id } = await setup({
      skipAuggieMock: true,
      moduleVariables: {
        install_auggie: "true",
        auggie_version: version_to_install,
        pre_install_script: dedent`
          #!/usr/bin/env bash
          set -euo pipefail
          
          # Install Node.js and npm via system package manager
          if ! command -v node >/dev/null 2>&1; then
            sudo apt-get update
            sudo apt-get install -y nodejs npm
          fi
          
          # Configure npm to use user directory (avoids permission issues)
          mkdir -p "$HOME/.npm-global"
          npm config set prefix "$HOME/.npm-global"
          
          # Persist npm user directory configuration
          echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.bashrc
          echo "prefix=$HOME/.npm-global" > ~/.npmrc
        `,
      },
    });
    await execModuleScript(id);
    const resp = await execContainer(id, [
      "bash",
      "-c",
      `cat /home/coder/.auggie-module/install.log`,
    ]);
    expect(resp.stdout).toContain(version_to_install);
  });

  test("check-latest-auggie-version-works", async () => {
    const { id } = await setup({
      skipAuggieMock: true,
      skipAgentAPIMock: true,
      moduleVariables: {
        install_auggie: "true",
        pre_install_script: dedent`
          #!/usr/bin/env bash
          set -euo pipefail
          
          # Install Node.js and npm via system package manager
          if ! command -v node >/dev/null 2>&1; then
            sudo apt-get update
            sudo apt-get install -y nodejs npm
          fi
          
          # Configure npm to use user directory (avoids permission issues)
          mkdir -p "$HOME/.npm-global"
          npm config set prefix "$HOME/.npm-global"
          
          # Persist npm user directory configuration
          echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> ~/.bashrc
          echo "prefix=$HOME/.npm-global" > ~/.npmrc
        `,
      },
    });
    await execModuleScript(id);
    await expectAgentAPIStarted(id);
  });

  test("auggie-session-token", async () => {
    const sessionToken = "test-session-token-123";
    const { id } = await setup({
      moduleVariables: {
        augment_session_token: sessionToken,
      },
    });
    await execModuleScript(id);

    const envCheck = await execContainer(id, [
      "bash",
      "-c",
      `env | grep AUGMENT_SESSION_AUTH || echo "AUGMENT_SESSION_AUTH not found"`,
    ]);
    expect(envCheck.stdout).toContain("AUGMENT_SESSION_AUTH");
  });

  test("auggie-mcp-config", async () => {
    const mcpConfig = JSON.stringify({
      mcpServers: {
        test: {
          command: "test-cmd",
          type: "stdio",
        },
      },
    });
    const { id } = await setup({
      moduleVariables: {
        mcp: mcpConfig,
      },
    });
    await execModuleScript(id);

    const resp = await readFileContainer(
      id,
      "/home/coder/.auggie-module/agentapi-start.log",
    );
    expect(resp).toContain("--mcp-config");
  });

  test("auggie-rules", async () => {
    const rules = "Always use TypeScript for new files";
    const { id } = await setup({
      moduleVariables: {
        install_auggie: "false", // Don't need to install auggie to test rules file creation
        rules: rules,
      },
    });
    await execModuleScript(id);

    const rulesFile = await readFileContainer(
      id,
      "/home/coder/.augment/rules.md",
    );
    expect(rulesFile).toContain(rules);
  });

  test("auggie-ai-task-prompt", async () => {
    const prompt = "This is a task prompt for Auggie.";
    const { id } = await setup({
      moduleVariables: {
        ai_prompt: prompt,
      },
    });
    await execModuleScript(id);

    const resp = await execContainer(id, [
      "bash",
      "-c",
      `cat /home/coder/.auggie-module/agentapi-start.log`,
    ]);
    expect(resp.stdout).toContain(prompt);
  });

  test("auggie-interaction-mode", async () => {
    const mode = "compact";
    const { id } = await setup({
      moduleVariables: {
        interaction_mode: mode,
        ai_prompt: "test prompt",
      },
    });
    await execModuleScript(id);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.auggie-module/agentapi-start.log",
    ]);
    expect(startLog.stdout).toContain(`--${mode}`);
  });

  test("auggie-model", async () => {
    const model = "gpt-4";
    const { id } = await setup({
      moduleVariables: {
        auggie_model: model,
        ai_prompt: "test prompt",
      },
    });
    await execModuleScript(id);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.auggie-module/agentapi-start.log",
    ]);
    expect(startLog.stdout).toContain(`--model ${model}`);
  });

  test("auggie-continue-previous-conversation", async () => {
    const { id } = await setup({
      moduleVariables: {
        continue_previous_conversation: "true",
        ai_prompt: "test prompt",
      },
    });
    await execModuleScript(id);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.auggie-module/agentapi-start.log",
    ]);
    expect(startLog.stdout).toContain("--continue");
  });

  test("pre-post-install-scripts", async () => {
    const { id } = await setup({
      moduleVariables: {
        pre_install_script: "#!/bin/bash\necho 'auggie-pre-install-script'",
        post_install_script: "#!/bin/bash\necho 'auggie-post-install-script'",
      },
    });
    await execModuleScript(id);

    const preInstallLog = await readFileContainer(
      id,
      "/home/coder/.auggie-module/pre_install.log",
    );
    expect(preInstallLog).toContain("auggie-pre-install-script");

    const postInstallLog = await readFileContainer(
      id,
      "/home/coder/.auggie-module/post_install.log",
    );
    expect(postInstallLog).toContain("auggie-post-install-script");
  });

  test("folder-variable", async () => {
    const folder = "/home/coder/auggie-test-folder";
    const { id } = await setup({
      skipAuggieMock: false,
      moduleVariables: {
        folder,
      },
    });
    await execModuleScript(id);

    const resp = await readFileContainer(
      id,
      "/home/coder/.auggie-module/agentapi-start.log",
    );
    expect(resp).toContain(folder);
  });

  test("coder-mcp-config-created", async () => {
    const { id } = await setup({
      moduleVariables: {
        install_auggie: "false", // Don't need to install auggie to test MCP config creation
      },
    });
    await execModuleScript(id);

    const mcpConfig = await readFileContainer(
      id,
      "/home/coder/.augment/coder_mcp.json",
    );
    expect(mcpConfig).toContain("mcpServers");
    expect(mcpConfig).toContain("coder");
    expect(mcpConfig).toContain("CODER_MCP_APP_STATUS_SLUG");
    expect(mcpConfig).toContain("CODER_MCP_AI_AGENTAPI_URL");
  });

  test("mcp-files-array", async () => {
    const mcpFiles = ["/path/to/mcp1.json", "/path/to/mcp2.json"];
    const { id } = await setup({
      moduleVariables: {
        mcp_files: JSON.stringify(mcpFiles),
        ai_prompt: "test prompt",
      },
    });
    await execModuleScript(id);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.auggie-module/agentapi-start.log",
    ]);
    expect(startLog.stdout).toContain("mcp1.json");
    expect(startLog.stdout).toContain("mcp2.json");
  });
});
