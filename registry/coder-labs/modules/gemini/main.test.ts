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
  skipGeminiMock?: boolean;
  moduleVariables?: Record<string, string>;
  agentapiMockScript?: string;
}

const setup = async (props?: SetupProps): Promise<{ id: string }> => {
  const projectDir = "/home/coder/project";
  const { id } = await setupUtil({
    moduleDir: import.meta.dir,
    moduleVariables: {
      install_gemini: props?.skipGeminiMock ? "true" : "false",
      install_agentapi: props?.skipAgentAPIMock ? "true" : "false",
      gemini_model: "test-model",
      ...props?.moduleVariables,
    },
    registerCleanup,
    projectDir,
    skipAgentAPIMock: props?.skipAgentAPIMock,
    agentapiMockScript: props?.agentapiMockScript,
  });
  if (!props?.skipGeminiMock) {
    const geminiMockContent = `#!/bin/bash

if [[ "$1" == "--version" ]]; then
  echo "HELLO: $(bash -c env)"
  echo "gemini version v2.5.0"
  exit 0
fi

set -e

while true; do
    echo "$(date) - gemini-mock"
    sleep 15
done`;
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/gemini",
      content: geminiMockContent,
    });
  }
  return { id };
};

setDefaultTimeout(60 * 1000);

describe("gemini", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("agent-api", async () => {
    const { id } = await setup();
    await execModuleScript(id);
    await expectAgentAPIStarted(id);
  });

  test("install-gemini-version", async () => {
    const version_to_install = "0.1.13";
    const { id } = await setup({
      skipGeminiMock: true,
      moduleVariables: {
        install_gemini: "true",
        gemini_version: version_to_install,
      },
    });
    await execModuleScript(id);
    const resp = await execContainer(id, [
      "bash",
      "-c",
      `cat /home/coder/.gemini-module/install.log || true`,
    ]);
    expect(resp.stdout).toContain(version_to_install);
  });

  test("install-gemini-latest", async () => {
    const { id } = await setup({
      skipGeminiMock: true,
      moduleVariables: {
        install_gemini: "true",
        gemini_version: "",
      },
    });
    await execModuleScript(id);
    await expectAgentAPIStarted(id);
  });

  test("gemini-settings-json", async () => {
    const settings = '{"foo": "bar"}';
    const { id } = await setup({
      moduleVariables: {
        gemini_settings_json: settings,
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(
      id,
      "/home/coder/.gemini/settings.json",
    );
    expect(resp).toContain("foo");
    expect(resp).toContain("bar");
  });

  test("gemini-api-key", async () => {
    const apiKey = "test-api-key-123";
    const { id } = await setup({
      moduleVariables: {
        gemini_api_key: apiKey,
      },
    });
    await execModuleScript(id);

    const resp = await readFileContainer(
      id,
      "/home/coder/.gemini-module/agentapi-start.log",
    );
    expect(resp).toContain("Using direct Gemini API with API key");
  });

  test("use-vertexai", async () => {
    const { id } = await setup({
      skipGeminiMock: false,
      moduleVariables: {
        use_vertexai: "true",
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(
      id,
      "/home/coder/.gemini-module/agentapi-start.log",
    );
    expect(resp).toContain("GOOGLE_GENAI_USE_VERTEXAI='true'");
  });

  test("gemini-model", async () => {
    const model = "gemini-2.5-pro";
    const { id } = await setup({
      skipGeminiMock: false,
      moduleVariables: {
        gemini_model: model,
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(
      id,
      "/home/coder/.gemini-module/agentapi-start.log",
    );
    expect(resp).toContain(model);
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
      "/home/coder/.gemini-module/pre_install.log",
    );
    expect(preInstallLog).toContain("pre-install-script");
    const postInstallLog = await readFileContainer(
      id,
      "/home/coder/.gemini-module/post_install.log",
    );
    expect(postInstallLog).toContain("post-install-script");
  });

  test("folder-variable", async () => {
    const folder = "/tmp/gemini-test-folder";
    const { id } = await setup({
      skipGeminiMock: false,
      moduleVariables: {
        folder,
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(
      id,
      "/home/coder/.gemini-module/agentapi-start.log",
    );
    expect(resp).toContain(folder);
  });

  test("additional-extensions", async () => {
    const additional = '{"custom": {"enabled": true}}';
    const { id } = await setup({
      moduleVariables: {
        additional_extensions: additional,
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(
      id,
      "/home/coder/.gemini/settings.json",
    );
    expect(resp).toContain("custom");
    expect(resp).toContain("enabled");
  });

  test("gemini-system-prompt", async () => {
    const prompt = "This is a system prompt for Gemini.";
    const { id } = await setup({
      moduleVariables: {
        gemini_system_prompt: prompt,
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(id, "/home/coder/GEMINI.md");
    expect(resp).toContain(prompt);
  });

  test("task-prompt", async () => {
    const taskPrompt = "Create a simple Hello World function";
    const { id } = await setup({
      moduleVariables: {
        task_prompt: taskPrompt,
      },
    });
    await execModuleScript(id, {
      GEMINI_TASK_PROMPT: taskPrompt,
    });
    const resp = await readFileContainer(
      id,
      "/home/coder/.gemini-module/agentapi-start.log",
    );
    expect(resp).toContain("Running automated task:");
  });

  test("start-without-prompt", async () => {
    const { id } = await setup();
    await execModuleScript(id);
    const prompt = await execContainer(id, [
      "ls",
      "-l",
      "/home/coder/GEMINI.md",
    ]);
    expect(prompt.exitCode).not.toBe(0);
    expect(prompt.stderr).toContain("No such file or directory");
  });
});
