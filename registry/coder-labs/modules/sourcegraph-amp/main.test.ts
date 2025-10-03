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
  skipAmpMock?: boolean;
  moduleVariables?: Record<string, string>;
  agentapiMockScript?: string;
}

const setup = async (props?: SetupProps): Promise<{ id: string }> => {
  const projectDir = "/home/coder/project";
  const { id } = await setupUtil({
    moduleDir: import.meta.dir,
    moduleVariables: {
      workdir: "/home/coder",
      install_amp: props?.skipAmpMock ? "true" : "false",
      install_agentapi: props?.skipAgentAPIMock ? "true" : "false",
      ...props?.moduleVariables,
    },
    registerCleanup,
    projectDir,
    skipAgentAPIMock: props?.skipAgentAPIMock,
    agentapiMockScript: props?.agentapiMockScript,
  });

  // Place the AMP mock CLI binary inside the container
  if (!props?.skipAmpMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/amp",
      content: await loadTestFile(`${import.meta.dir}`, "amp-mock.sh"),
    });
  }

  return { id };
};

setDefaultTimeout(60 * 1000);

describe("amp", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  // test("happy-path", async () => {
  //   const { id } = await setup();
  //   await execModuleScript(id);
  //   await expectAgentAPIStarted(id);
  // });
  //
  // test("api-key", async () => {
  //   const apiKey = "test-api-key-123";
  //   const { id } = await setup({
  //     moduleVariables: {
  //       amp_api_key: apiKey,
  //     },
  //   });
  //   await execModuleScript(id);
  //   const resp = await readFileContainer(
  //     id,
  //     "/home/coder/.amp-module/agentapi-start.log",
  //   );
  //   expect(resp).toContain("amp_api_key provided !");
  // });
  //
  test("install-latest-version", async () => {
    const { id } = await setup({
      skipAmpMock: true,
      skipAgentAPIMock: true,
      moduleVariables: {
        amp_version: "",
      },
    });
    await execModuleScript(id);
    await expectAgentAPIStarted(id);
  });

  test("install-specific-version", async () => {
    const { id } = await setup({
      skipAmpMock: true,
      moduleVariables: {
        amp_version: "0.0.1755964909-g31e083",
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(
      id,
      "/home/coder/.amp-module/agentapi-start.log",
    );
    expect(resp).toContain("0.0.1755964909-g31e08");
  });

  test("custom-workdir", async () => {
    const workdir = "/tmp/amp-test";
    const { id } = await setup({
      moduleVariables: {
        workdir,
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(
      id,
      "/home/coder/.amp-module/agentapi-start.log",
    );
    expect(resp).toContain(workdir);
  });

  test("pre-post-install-scripts", async () => {
    const { id } = await setup({
      moduleVariables: {
        pre_install_script: "#!/bin/bash\necho 'pre-install-script'",
        post_install_script: "#!/bin/bash\necho 'post-install-script'",
      },
    });
    await execModuleScript(id);
    const preLog = await readFileContainer(
      id,
      "/home/coder/.amp-module/pre_install.log",
    );
    expect(preLog).toContain("pre-install-script");
    const postLog = await readFileContainer(
      id,
      "/home/coder/.amp-module/post_install.log",
    );
    expect(postLog).toContain("post-install-script");
  });

  test("instruction-prompt", async () => {
    const prompt = "this is a instruction prompt for AMP";
    const { id } = await setup({
      moduleVariables: {
        instruction_prompt: prompt,
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(id, "/home/coder/.config/AGENTS.md");
    expect(resp).toContain(prompt);
  });

  test("ai-prompt", async () => {
    const prompt = "this is a task prompt for AMP";
    const { id } = await setup({
      moduleVariables: {
        ai_prompt: prompt,
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(
      id,
      "/home/coder/.amp-module/agentapi-start.log",
    );
    expect(resp).toContain(`amp task prompt provided : ${prompt}`);
  });

  test("custom-base-config", async () => {
    const customConfig = JSON.stringify({
      "amp.anthropic.thinking.enabled": false,
      "amp.todos.enabled": false,
      "amp.tools.stopTimeout": 900,
      "amp.git.commit.ampThread.enabled": true,
    });
    const customMcp = JSON.stringify({
      "test-server": {
        command: "/usr/bin/test-mcp",
        args: ["--test-arg"],
        type: "stdio",
      },
    });
    const { id } = await setup({
      moduleVariables: {
        base_amp_config: customConfig,
        mcp: customMcp,
      },
    });
    await execModuleScript(id, {
      CODER_AGENT_TOKEN: "test-token",
      CODER_AGENT_URL: "http://test-url:3000",
    });
    const settingsContent = await readFileContainer(
      id,
      "/home/coder/.config/amp/settings.json",
    );
    const settings = JSON.parse(settingsContent);

    expect(settings["amp.anthropic.thinking.enabled"]).toBe(false);
    expect(settings["amp.todos.enabled"]).toBe(false);
    expect(settings["amp.tools.stopTimeout"]).toBe(900);
    expect(settings["amp.git.commit.ampThread.enabled"]).toBe(true);
    expect(settings["amp.mcpServers"]).toBeDefined();
    expect(settings["amp.mcpServers"].coder).toBeDefined();
    expect(settings["amp.mcpServers"]["test-server"]).toBeDefined();
    expect(settings["amp.mcpServers"]["test-server"].command).toBe(
      "/usr/bin/test-mcp",
    );
    expect(settings["amp.mcpServers"]["test-server"].args).toEqual([
      "--test-arg",
    ]);
  });

  test("default-base-config", async () => {
    const { id } = await setup();
    await execModuleScript(id, {
      CODER_AGENT_TOKEN: "test-token",
      CODER_AGENT_URL: "http://test-url:3000",
    });
    const settingsContent = await readFileContainer(
      id,
      "/home/coder/.config/amp/settings.json",
    );
    const settings = JSON.parse(settingsContent);

    expect(settings["amp.anthropic.thinking.enabled"]).toBe(true);
    expect(settings["amp.todos.enabled"]).toBe(true);
    expect(settings["amp.mcpServers"]).toBeDefined();
    expect(settings["amp.mcpServers"].coder).toBeDefined();
    expect(settings["amp.mcpServers"].coder.command).toBe("coder");
  });
});
