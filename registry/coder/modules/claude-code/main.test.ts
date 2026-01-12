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

  test("run-with-boundary", async () => {
    const { id, coderEnvVars } = await setup({
      skipAgentAPIMock: true,
      skipClaudeMock: true,
      moduleVariables: {
        enable_boundary: "true",
      },
    });
    await execModuleScript(id, coderEnvVars);

    await expectAgentAPIStarted(id);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.claude-module/agentapi-start.log",
    ]);
    expect(startLog.stdout).toContain(
      `boundary-run wrapper is available in PATH`,
    );
  });
});
