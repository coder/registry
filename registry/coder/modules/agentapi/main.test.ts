import {
  test,
  afterEach,
  expect,
  describe,
  setDefaultTimeout,
  beforeAll,
} from "bun:test";
import { execContainer, readFileContainer, runTerraformInit } from "~test";
import {
  loadTestFile,
  writeExecutable,
  setup as setupUtil,
  execModuleScript,
  expectAgentAPIStarted,
} from "./test-util";

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
  moduleVariables?: Record<string, string>;
}

const moduleDirName = ".agentapi-module";

const setup = async (props?: SetupProps): Promise<{ id: string }> => {
  const projectDir = "/home/coder/project";
  const { id } = await setupUtil({
    moduleVariables: {
      experiment_report_tasks: "true",
      install_agentapi: props?.skipAgentAPIMock ? "true" : "false",
      web_app_display_name: "AgentAPI Web",
      web_app_slug: "agentapi-web",
      web_app_icon: "/icon/coder.svg",
      cli_app_display_name: "AgentAPI CLI",
      cli_app_slug: "agentapi-cli",
      agentapi_version: "latest",
      module_dir_name: moduleDirName,
      start_script: await loadTestFile(import.meta.dir, "agentapi-start.sh"),
      folder: projectDir,
      ...props?.moduleVariables,
    },
    registerCleanup,
    projectDir,
    skipAgentAPIMock: props?.skipAgentAPIMock,
    moduleDir: import.meta.dir,
  });
  await writeExecutable({
    containerId: id,
    filePath: "/usr/bin/aiagent",
    content: await loadTestFile(import.meta.dir, "ai-agent-mock.js"),
  });
  return { id };
};

// increase the default timeout to 60 seconds
setDefaultTimeout(60 * 1000);

// we don't run these tests in CI because they take too long and make network
// calls. they are dedicated for local development.
describe("agentapi", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path", async () => {
    const { id } = await setup();

    await execModuleScript(id);

    await expectAgentAPIStarted(id);
  });

  test("custom-port", async () => {
    const { id } = await setup({
      moduleVariables: {
        agentapi_port: "3827",
      },
    });
    await execModuleScript(id);
    await expectAgentAPIStarted(id, 3827);
  });

  test("pre-post-install-scripts", async () => {
    const { id } = await setup({
      moduleVariables: {
        pre_install_script: `#!/bin/bash\necho "pre-install"`,
        install_script: `#!/bin/bash\necho "install"`,
        post_install_script: `#!/bin/bash\necho "post-install"`,
      },
    });

    await execModuleScript(id);
    await expectAgentAPIStarted(id);

    const preInstallLog = await readFileContainer(
      id,
      `/home/coder/${moduleDirName}/pre_install.log`,
    );
    const installLog = await readFileContainer(
      id,
      `/home/coder/${moduleDirName}/install.log`,
    );
    const postInstallLog = await readFileContainer(
      id,
      `/home/coder/${moduleDirName}/post_install.log`,
    );

    expect(preInstallLog).toContain("pre-install");
    expect(installLog).toContain("install");
    expect(postInstallLog).toContain("post-install");
  });

  test("install-agentapi", async () => {
    const { id } = await setup({ skipAgentAPIMock: true });

    const respModuleScript = await execModuleScript(id);
    expect(respModuleScript.exitCode).toBe(0);

    await expectAgentAPIStarted(id);
    const respAgentAPI = await execContainer(id, [
      "bash",
      "-c",
      "agentapi --version",
    ]);
    expect(respAgentAPI.exitCode).toBe(0);
  });

  test("no-subdomain-base-path", async () => {
    const { id } = await setup({
      moduleVariables: {
        agentapi_subdomain: "false",
      },
    });

    const respModuleScript = await execModuleScript(id);
    expect(respModuleScript.exitCode).toBe(0);

    await expectAgentAPIStarted(id);
    const agentApiStartLog = await readFileContainer(
      id,
      "/home/coder/test-agentapi-start.log",
    );
    expect(agentApiStartLog).toContain("Using AGENTAPI_CHAT_BASE_PATH: /@default/default.foo/apps/agentapi-web/chat");
  });

  test("validate-agentapi-version", async () => {
    const cases = [
      {
        moduleVariables: {
          agentapi_version: "v0.3.2",
        },
        shouldThrow: "",
      },
      {
        moduleVariables: {
          agentapi_version: "v0.3.3",
        },
        shouldThrow: "",
      },
      {
        moduleVariables: {
          agentapi_version: "v0.0.1",
          agentapi_subdomain: "false",
        },
        shouldThrow: "Running with subdomain = false is only supported by agentapi >= v0.3.3.",
      },
      {
        moduleVariables: {
          agentapi_version: "v0.3.2",
          agentapi_subdomain: "false",
        },
        shouldThrow: "Running with subdomain = false is only supported by agentapi >= v0.3.3.",
      },
      {
        moduleVariables: {
          agentapi_version: "v0.3.3",
          agentapi_subdomain: "false",
        },
        shouldThrow: "",
      },
      {
        moduleVariables: {
          agentapi_version: "v0.3.999",
          agentapi_subdomain: "false",
        },
        shouldThrow: "",
      },
      {
        moduleVariables: {
          agentapi_version: "v0.999.999",
          agentapi_subdomain: "false",
        },
      },
      {
        moduleVariables: {
          agentapi_version: "v999.999.999",
          agentapi_subdomain: "false",
        },
      },
      {
        moduleVariables: {
          agentapi_version: "arbitrary-string-bypasses-validation",
        },
        shouldThrow: "",
      }
    ];
    for (const { moduleVariables, shouldThrow } of cases) {
      if (shouldThrow) {
        expect(setup({ moduleVariables: moduleVariables as Record<string, string> })).rejects.toThrow(shouldThrow);
      } else {
        expect(setup({ moduleVariables: moduleVariables as Record<string, string> })).resolves.toBeDefined();
      }
    }
  });

  test("agentapi-allowed-hosts", async () => {
    // verify that the agentapi binary has access to the AGENTAPI_ALLOWED_HOSTS environment variable
    // set in main.sh
    const { id } = await setup();
    await execModuleScript(id);
    await expectAgentAPIStarted(id);
    const agentApiStartLog = await readFileContainer(
      id,
      "/home/coder/agentapi-mock.log",
    );
    expect(agentApiStartLog).toContain("AGENTAPI_ALLOWED_HOSTS: *");
  });
});
