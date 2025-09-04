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
  skipAiderMock?: boolean;
  moduleVariables?: Record<string, string>;
  agentapiMockScript?: string;
}

const setup = async (props?: SetupProps): Promise<{ id: string }> => {
  const projectDir = "/home/coder/project";
  const { id } = await setupUtil({
    moduleDir: import.meta.dir,
    moduleVariables: {
      install_aider: props?.skipAiderMock ? "true" : "false",
      install_agentapi: props?.skipAgentAPIMock ? "true" : "false",
      aider_model: "test-model",
      ...props?.moduleVariables,
    },
    registerCleanup,
    projectDir,
    skipAgentAPIMock: props?.skipAgentAPIMock,
    agentapiMockScript: props?.agentapiMockScript,
  });

  // Place the Aider mock CLI binary inside the container
  if (!props?.skipAiderMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/aider",
      content: await loadTestFile(`${import.meta.dir}`, "aider-mock.sh"),
    });
  }

  return { id };
};

setDefaultTimeout(60 * 1000);

describe("Aider", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path", async () => {
    const { id } = await setup({
      moduleVariables: {
        model: "gemini",
      },
    });
    await execModuleScript(id);
    await expectAgentAPIStarted(id);
  });

  test("api-key", async () => {
    const apiKey = "test-api-key-123";
    const { id } = await setup({
      moduleVariables: {
        credentials: apiKey,
        model: "gemini",
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(
      id,
      "/home/coder/.aider-module/agentapi-start.log",
    );
    expect(resp).toContain("API key provided !");
  });

  test("custom-folder", async () => {
    const folder = "/tmp/aider-test";
    const { id } = await setup({
      moduleVariables: {
        folder,
        model: "gemini",
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(
      id,
      "/home/coder/.aider-module/install.log",
    );
    expect(resp).toContain(folder);
  });

  test("pre-post-install-scripts", async () => {
    const { id } = await setup({
      moduleVariables: {
        experiment_pre_install_script: "#!/bin/bash\necho 'pre-install-script'",
        experiment_post_install_script:
          "#!/bin/bash\necho 'post-install-script'",
        model: "gemini",
      },
    });
    await execModuleScript(id);
    const preLog = await readFileContainer(
      id,
      "/home/coder/.aider-module/pre_install.log",
    );
    expect(preLog).toContain("pre-install-script");
    const postLog = await readFileContainer(
      id,
      "/home/coder/.aider-module/post_install.log",
    );
    expect(postLog).toContain("post-install-script");
  });

  test("system-prompt", async () => {
    const system_prompt = "this is a system prompt for Aider";
    const { id } = await setup({
      moduleVariables: {
        system_prompt,
        model: "gemini",
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(
      id,
      "/home/coder/.aider-module/SYSTEM_PROMPT.md",
    );
    expect(resp).toContain(system_prompt);
  });

  test("task-prompt", async () => {
    const prompt = "this is a task prompt for Aider";
    const apiKey = "test-api-key-123";
    const { id } = await setup({
      moduleVariables: {
        credentials: apiKey,
        model: "gemini",
      },
    });
    await execModuleScript(id, {
      ARG_TASK_PROMPT: `${prompt}`,
    });
    const resp = await readFileContainer(
      id,
      "/home/coder/.aider-module/agentapi-start.log",
    );
    expect(resp).toContain(`Aider task prompt provided : ${prompt}`);
  });
});
