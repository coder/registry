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

  test("cache-dir-uses-cached-binary", async () => {
    // Verify that when a cached binary exists in the cache dir, it is used
    // instead of downloading.
    const cacheDir = "/home/coder/.agentapi-cache";
    const { id } = await setup({
      moduleVariables: {
        agentapi_cache_dir: cacheDir,
      },
    });

    // Pre-populate the cache directory with a fake agentapi binary.
    // The binary is named after the arch: agentapi-linux-amd64-latest
    await execContainer(id, [
      "bash",
      "-c",
      `mkdir -p ${cacheDir} && cp /usr/bin/agentapi ${cacheDir}/agentapi-linux-amd64-latest`,
    ]);

    const respModuleScript = await execModuleScript(id);
    expect(respModuleScript.exitCode).toBe(0);
    expect(respModuleScript.stdout).toContain(
      `Using cached AgentAPI binary from ${cacheDir}/agentapi-linux-amd64-latest`,
    );

    await expectAgentAPIStarted(id);
  });

  test("cache-dir-saves-binary-after-download", async () => {
    // Verify that after downloading agentapi, the binary is saved to the cache dir.
    const cacheDir = "/home/coder/.agentapi-cache";
    const { id } = await setup({
      skipAgentAPIMock: true,
      moduleVariables: {
        agentapi_cache_dir: cacheDir,
      },
    });

    const respModuleScript = await execModuleScript(id);
    expect(respModuleScript.exitCode).toBe(0);
    expect(respModuleScript.stdout).toContain(
      `Caching AgentAPI binary to ${cacheDir}/agentapi-linux-amd64-latest`,
    );

    await expectAgentAPIStarted(id);

    // Verify the binary was saved to the cache directory.
    const respCacheCheck = await execContainer(id, [
      "bash",
      "-c",
      `test -f ${cacheDir}/agentapi-linux-amd64-latest && echo "cached"`,
    ]);
    expect(respCacheCheck.exitCode).toBe(0);
    expect(respCacheCheck.stdout).toContain("cached");
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
    expect(agentApiStartLog).toContain(
      "Using AGENTAPI_CHAT_BASE_PATH: /@default/default.foo/apps/agentapi-web/chat",
    );
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
        shouldThrow:
          "Running with subdomain = false is only supported by agentapi >= v0.3.3.",
      },
      {
        moduleVariables: {
          agentapi_version: "v0.3.2",
          agentapi_subdomain: "false",
        },
        shouldThrow:
          "Running with subdomain = false is only supported by agentapi >= v0.3.3.",
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
      },
    ];
    for (const { moduleVariables, shouldThrow } of cases) {
      if (shouldThrow) {
        expect(
          setup({ moduleVariables: moduleVariables as Record<string, string> }),
        ).rejects.toThrow(shouldThrow);
      } else {
        expect(
          setup({ moduleVariables: moduleVariables as Record<string, string> }),
        ).resolves.toBeDefined();
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

  describe("shutdown script", async () => {
    const setupMocks = async (
      containerId: string,
      agentapiPreset: string,
      httpCode: number = 204,
    ) => {
      const agentapiMock = await loadTestFile(
        import.meta.dir,
        "agentapi-mock-shutdown.js",
      );
      const coderMock = await loadTestFile(
        import.meta.dir,
        "coder-instance-mock.js",
      );

      await writeExecutable({
        containerId,
        filePath: "/usr/local/bin/mock-agentapi",
        content: agentapiMock,
      });

      await writeExecutable({
        containerId,
        filePath: "/usr/local/bin/mock-coder",
        content: coderMock,
      });

      await execContainer(containerId, [
        "bash",
        "-c",
        `PRESET=${agentapiPreset} nohup node /usr/local/bin/mock-agentapi 3284 > /tmp/mock-agentapi.log 2>&1 &`,
      ]);

      await execContainer(containerId, [
        "bash",
        "-c",
        `HTTP_CODE=${httpCode} nohup node /usr/local/bin/mock-coder 18080 > /tmp/mock-coder.log 2>&1 &`,
      ]);

      await new Promise((resolve) => setTimeout(resolve, 1000));
    };

    const runShutdownScript = async (
      containerId: string,
      taskId: string = "test-task",
    ) => {
      const shutdownScript = await loadTestFile(
        import.meta.dir,
        "../scripts/agentapi-shutdown.sh",
      );

      await writeExecutable({
        containerId,
        filePath: "/tmp/shutdown.sh",
        content: shutdownScript,
      });

      return await execContainer(containerId, [
        "bash",
        "-c",
        `ARG_TASK_ID=${taskId} ARG_AGENTAPI_PORT=3284 CODER_AGENT_URL=http://localhost:18080 CODER_AGENT_TOKEN=test-token /tmp/shutdown.sh`,
      ]);
    };

    test("posts snapshot with normal messages", async () => {
      const { id } = await setup({
        moduleVariables: {},
        skipAgentAPIMock: true,
      });

      await setupMocks(id, "normal");
      const result = await runShutdownScript(id);

      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain("Retrieved 5 messages for log snapshot");
      expect(result.stdout).toContain("Log snapshot posted successfully");

      const posted = await readFileContainer(id, "/tmp/snapshot-posted.json");
      const snapshot = JSON.parse(posted);
      expect(snapshot.task_id).toBe("test-task");
      expect(snapshot.payload.messages).toHaveLength(5);
      expect(snapshot.payload.messages[0].content).toBe("Hello");
      expect(snapshot.payload.messages[4].content).toBe("Great");
    });

    test("truncates to last 10 messages", async () => {
      const { id } = await setup({
        moduleVariables: {},
        skipAgentAPIMock: true,
      });

      await setupMocks(id, "many");
      const result = await runShutdownScript(id);

      expect(result.exitCode).toBe(0);

      const posted = await readFileContainer(id, "/tmp/snapshot-posted.json");
      const snapshot = JSON.parse(posted);
      expect(snapshot.task_id).toBe("test-task");
      expect(snapshot.payload.messages).toHaveLength(10);
      expect(snapshot.payload.messages[0].content).toBe("Message 6");
      expect(snapshot.payload.messages[9].content).toBe("Message 15");
    });

    test("truncates huge message content", async () => {
      const { id } = await setup({
        moduleVariables: {},
        skipAgentAPIMock: true,
      });

      await setupMocks(id, "huge");
      const result = await runShutdownScript(id);

      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain("truncating final message content");

      const posted = await readFileContainer(id, "/tmp/snapshot-posted.json");
      const snapshot = JSON.parse(posted);
      expect(snapshot.task_id).toBe("test-task");
      expect(snapshot.payload.messages).toHaveLength(1);
      expect(snapshot.payload.messages[0].content).toContain(
        "[...content truncated",
      );
    });

    test("skips gracefully when TASK_ID is empty", async () => {
      const { id } = await setup({
        moduleVariables: {},
        skipAgentAPIMock: true,
      });

      const result = await runShutdownScript(id, "");

      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain("No task ID, skipping log snapshot");
    });

    test("handles 404 gracefully for older Coder versions", async () => {
      const { id } = await setup({
        moduleVariables: {},
        skipAgentAPIMock: true,
      });

      await setupMocks(id, "normal", 404);
      const result = await runShutdownScript(id);

      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain(
        "Log snapshot endpoint not supported by this Coder version",
      );
    });
  });
});
