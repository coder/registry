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
  const { id } = await setupUtil({
    moduleDir: import.meta.dir,
    moduleVariables: {
      install_codex: props?.skipCodexMock ? "true" : "false",
      install_agentapi: props?.skipAgentAPIMock ? "true" : "false",
      codex_model: "gpt-4-turbo",
      folder: "/home/coder",
      ...props?.moduleVariables,
    },
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

  test("codex-config-toml", async () => {
    const settings = dedent`
      [mcp_servers.CustomMCP]
      command = "/Users/jkmr/Documents/work/coder/coder_darwin_arm64"
      args = ["exp", "mcp", "server", "app-status-slug=codex"]
      env = { "CODER_MCP_APP_STATUS_SLUG" = "codex", "CODER_MCP_AI_AGENTAPI_URL"= "http://localhost:3284" }
      description = "Report ALL tasks and statuses (in progress, done, failed) you are working on."
      enabled = true
      type = "stdio"
    `.trim();
    const { id } = await setup({
      moduleVariables: {
        extra_codex_settings_toml: settings,
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(id, "/home/coder/.codex/config.toml");
    expect(resp).toContain("[mcp_servers.CustomMCP]");
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
    expect(resp).toContain("openai_api_key provided !");
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

  test("folder-variable", async () => {
    const folder = "/tmp/codex-test-folder";
    const { id } = await setup({
      skipCodexMock: false,
      moduleVariables: {
        folder,
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(
      id,
      "/home/coder/.codex-module/install.log",
    );
    expect(resp).toContain(folder);
  });

  test("additional-extensions", async () => {
    const additional = dedent`
      [mcp_servers.CustomMCP]
      command = "/Users/jkmr/Documents/work/coder/coder_darwin_arm64"
      args = ["exp", "mcp", "server", "app-status-slug=codex"]
      env = { "CODER_MCP_APP_STATUS_SLUG" = "codex", "CODER_MCP_AI_AGENTAPI_URL"= "http://localhost:3284" }
      description = "Report ALL tasks and statuses (in progress, done, failed) you are working on."
      enabled = true
      type = "stdio"
    `.trim();
    const { id } = await setup({
      moduleVariables: {
        additional_extensions: additional,
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(id, "/home/coder/.codex/config.toml");
    expect(resp).toContain("[mcp_servers.CustomMCP]");
    expect(resp).toContain("[mcp_servers.Coder]");
  });

  test("codex-system-prompt", async () => {
    const prompt = "This is a system prompt for Codex.";
    const { id } = await setup({
      moduleVariables: {
        codex_system_prompt: prompt,
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(id, "/home/coder/AGENTS.md");
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
        echo -e "${prompt_3}" >> /home/coder/AGENTS.md
        `.trim();

    const { id } = await setup({
      moduleVariables: {
        pre_install_script,
        codex_system_prompt: prompt_2,
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(id, "/home/coder/AGENTS.md");
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
    const resp_2 = await readFileContainer(id_2, "/home/coder/AGENTS.md");
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
    const { id } = await setup();
    await execModuleScript(id);
    const prompt = await execContainer(id, [
      "ls",
      "-l",
      "/home/coder/AGENTS.md",
    ]);
    expect(prompt.exitCode).not.toBe(0);
    expect(prompt.stderr).toContain("No such file or directory");
  });
});
