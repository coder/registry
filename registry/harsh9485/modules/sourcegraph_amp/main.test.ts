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
      install_sourcegraph_amp: props?.skipAmpMock ? "true" : "false",
      install_agentapi: props?.skipAgentAPIMock ? "true" : "false",
      sourcegraph_amp_model: "test-model",
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

describe("Sourcegraph AMP Module", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path", async () => {
    const { id } = await setup();
    await execModuleScript(id);
    await expectAgentAPIStarted(id);
  });
  
  test("sourcegraph-amp-api-key", async () => {
    const apiKey = "test-api-key-123";
    const { id } = await setup({
      moduleVariables: {
        sourcegraph_amp_api_key: apiKey,
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(id, "/home/coder/.sourcegraph-amp-module/agentapi-start.log");
    expect(resp).toContain("AMP version: AMP CLI mock version v1.0.0");
  });

  test("custom-folder", async () => {
    const folder = "/tmp/sourcegraph-amp-test";
    const { id } = await setup({
      moduleVariables: {
        folder,
      },
    });
    await execModuleScript(id);
    const resp = await readFileContainer(id, "/home/coder/.sourcegraph-amp-module/install.log");
    expect(resp).toContain(folder);
  });

  test("pre-post-install-scripts", async () => {
    const { id } = await setup({
      moduleVariables: {
        pre_install_script: "#!/bin/bash\necho 'pre-install-script'",
        post_install_script: "#!/bin/bash\necho 'post-install-script'",
      },
    });
    await execModuleScript(id);
    const preLog = await readFileContainer(id, "/home/coder/.sourcegraph-amp-module/pre_install.log");
    expect(preLog).toContain("pre-install-script");
    const postLog = await readFileContainer(id, "/home/coder/.sourcegraph-amp-module/post_install.log");
    expect(postLog).toContain("post-install-script");
  });

  test("amp-not-installed", async () => {
    const { id } = await setup({ skipAmpMock: true });
    await execModuleScript(id);
    const log = await readFileContainer(id, "/home/coder/.sourcegraph-amp-module/install.log");
    expect(log).toContain("Error");
  });
});
