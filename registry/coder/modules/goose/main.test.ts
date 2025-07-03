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

// Cleanup logic depends on the fact that bun's built-in test runner
// runs tests sequentially.
// https://bun.sh/docs/test/discovery#execution-order
// Weird things would happen if tried to run tests in parallel.
// One test could clean up resources that another test was still using.
afterEach(async () => {
  // reverse the cleanup functions so that they are run in the correct order
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
  skipGooseMock?: boolean;
  moduleVariables?: Record<string, string>;
  agentapiMockScript?: string;
}

const setup = async (props?: SetupProps): Promise<{ id: string }> => {
  const projectDir = "/home/coder/project";
  const { id } = await setupUtil({
    moduleDir: import.meta.dir,
    moduleVariables: {
      install_goose: props?.skipGooseMock ? "true" : "false",
      install_agentapi: props?.skipAgentAPIMock ? "true" : "false",
      goose_provider: "test-provider",
      goose_model: "test-model",
      ...props?.moduleVariables,
    },
    registerCleanup,
    projectDir,
    skipAgentAPIMock: props?.skipAgentAPIMock,
    agentapiMockScript: props?.agentapiMockScript,
  });
  if (!props?.skipGooseMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/goose",
      content: await loadTestFile(import.meta.dir, "goose-mock.sh"),
    });
  }
  return { id };
};

// increase the default timeout to 60 seconds
setDefaultTimeout(60 * 1000);

describe("goose", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path", async () => {
    const { id } = await setup();

    await execModuleScript(id);

    await expectAgentAPIStarted(id);
  });

  test("install-version", async () => {
    const { id } = await setup({
      skipGooseMock: true,
      moduleVariables: {
        install_goose: "true",
        goose_version: "v1.0.24",
      },
    });

    await execModuleScript(id);

    const resp = await execContainer(id, [
      "bash",
      "-c",
      `"$HOME/.local/bin/goose" --version`,
    ]);
    if (resp.exitCode !== 0) {
      console.log(resp.stdout);
      console.log(resp.stderr);
    }
    expect(resp.exitCode).toBe(0);
    expect(resp.stdout).toContain("1.0.24");
  });

  test("install-stable", async () => {
    const { id } = await setup({
      skipGooseMock: true,
      moduleVariables: {
        install_goose: "true",
        goose_version: "stable",
      },
    });

    await execModuleScript(id);

    const resp = await execContainer(id, [
      "bash",
      "-c",
      `"$HOME/.local/bin/goose" --version`,
    ]);
    if (resp.exitCode !== 0) {
      console.log(resp.stdout);
      console.log(resp.stderr);
    }
    expect(resp.exitCode).toBe(0);
  });

  test("config", async () => {
    const expected =
      dedent`
      GOOSE_PROVIDER: anthropic
      GOOSE_MODEL: claude-3-5-sonnet-latest
      extensions:
        coder:
          args:
          - exp
          - mcp
          - server
          cmd: coder
          description: Report ALL tasks and statuses (in progress, done, failed) you are working on.
          enabled: true
          envs:
            CODER_MCP_APP_STATUS_SLUG: goose
            CODER_MCP_AI_AGENTAPI_URL: http://localhost:3284
          name: Coder
          timeout: 3000
          type: stdio
        developer:
          display_name: Developer
          enabled: true
          name: developer
          timeout: 300
          type: builtin
        custom-stuff:
          enabled: true
          name: custom-stuff
          timeout: 300
          type: builtin
    `.trim() + "\n";

    const { id } = await setup({
      moduleVariables: {
        goose_provider: "anthropic",
        goose_model: "claude-3-5-sonnet-latest",
        additional_extensions: dedent`
          custom-stuff:
            enabled: true
            name: custom-stuff
            timeout: 300
            type: builtin
        `.trim(),
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(
      id,
      "/home/coder/.config/goose/config.yaml",
    );
    expect(resp).toEqual(expected);
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
      "/home/coder/.goose-module/pre_install.log",
    );
    expect(preInstallLog).toContain("pre-install-script");

    const postInstallLog = await readFileContainer(
      id,
      "/home/coder/.goose-module/post_install.log",
    );
    expect(postInstallLog).toContain("post-install-script");
  });

  const promptFile = "/home/coder/.goose-module/prompt.txt";
  const agentapiStartLog = "/home/coder/.goose-module/agentapi-start.log";

  test("start-with-prompt", async () => {
    const { id } = await setup({
      agentapiMockScript: await loadTestFile(
        import.meta.dir,
        "agentapi-mock-print-args.js",
      ),
    });
    await execModuleScript(id, {
      GOOSE_TASK_PROMPT: "custom-test-prompt",
    });
    const prompt = await readFileContainer(id, promptFile);
    expect(prompt).toContain("custom-test-prompt");

    const agentapiMockOutput = await readFileContainer(id, agentapiStartLog);
    expect(agentapiMockOutput).toContain(
      "'goose run --interactive --instructions /home/coder/.goose-module/prompt.txt '",
    );
  });

  test("start-without-prompt", async () => {
    const { id } = await setup({
      agentapiMockScript: await loadTestFile(
        import.meta.dir,
        "agentapi-mock-print-args.js",
      ),
    });
    await execModuleScript(id);

    const agentapiMockOutput = await readFileContainer(id, agentapiStartLog);
    expect(agentapiMockOutput).toContain("'goose '");

    const prompt = await execContainer(id, ["ls", "-l", promptFile]);
    expect(prompt.exitCode).not.toBe(0);
    expect(prompt.stderr).toContain("No such file or directory");
  });
});
