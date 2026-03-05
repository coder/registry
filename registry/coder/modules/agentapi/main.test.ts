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

  test("state-persistence-disabled", async () => {
    const { id } = await setup({
      moduleVariables: {
        enable_state_persistence: "false",
      },
    });
    await execModuleScript(id);
    await expectAgentAPIStarted(id);
    const mockLog = await readFileContainer(
      id,
      "/home/coder/agentapi-mock.log",
    );
    // PID file should always be exported
    expect(mockLog).toContain("AGENTAPI_PID_FILE:");
    // State vars should NOT be present when disabled
    expect(mockLog).not.toContain("AGENTAPI_STATE_FILE:");
    expect(mockLog).not.toContain("AGENTAPI_SAVE_STATE:");
    expect(mockLog).not.toContain("AGENTAPI_LOAD_STATE:");
  });

  test("state-persistence-custom-paths", async () => {
    const { id } = await setup({
      moduleVariables: {
        enable_state_persistence: "true",
        state_file_path: "/home/coder/custom/state.json",
        pid_file_path: "/home/coder/custom/agentapi.pid",
      },
    });
    await execModuleScript(id);
    await expectAgentAPIStarted(id);
    const mockLog = await readFileContainer(
      id,
      "/home/coder/agentapi-mock.log",
    );
    expect(mockLog).toContain(
      "AGENTAPI_STATE_FILE: /home/coder/custom/state.json",
    );
    expect(mockLog).toContain(
      "AGENTAPI_PID_FILE: /home/coder/custom/agentapi.pid",
    );
  });

  test("state-persistence-default-paths", async () => {
    const { id } = await setup({
      moduleVariables: {
        enable_state_persistence: "true",
      },
    });
    await execModuleScript(id);
    await expectAgentAPIStarted(id);
    const mockLog = await readFileContainer(
      id,
      "/home/coder/agentapi-mock.log",
    );
    expect(mockLog).toContain(
      `AGENTAPI_STATE_FILE: /home/coder/${moduleDirName}/agentapi-state.json`,
    );
    expect(mockLog).toContain(
      `AGENTAPI_PID_FILE: /home/coder/${moduleDirName}/agentapi.pid`,
    );
    expect(mockLog).toContain("AGENTAPI_SAVE_STATE: true");
    expect(mockLog).toContain("AGENTAPI_LOAD_STATE: true");
  });

  describe("shutdown script", async () => {
    const setupMocks = async (
      containerId: string,
      agentapiPreset: string,
      httpCode: number = 204,
      pidFilePath: string = "",
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

      const pidFileEnv = pidFilePath ? `AGENTAPI_PID_FILE=${pidFilePath}` : "";
      await execContainer(containerId, [
        "bash",
        "-c",
        `PRESET=${agentapiPreset} ${pidFileEnv} nohup node /usr/local/bin/mock-agentapi 3284 > /tmp/mock-agentapi.log 2>&1 &`,
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
      pidFilePath: string = "",
      enableStatePersistence: string = "false",
    ) => {
      const shutdownScript = await loadTestFile(
        import.meta.dir,
        "../scripts/agentapi-shutdown.sh",
      );

      const libScript = await loadTestFile(
        import.meta.dir,
        "../scripts/lib.sh",
      );

      await writeExecutable({
        containerId,
        filePath: "/tmp/agentapi-lib.sh",
        content: libScript,
      });

      await writeExecutable({
        containerId,
        filePath: "/tmp/shutdown.sh",
        content: shutdownScript,
      });

      return await execContainer(containerId, [
        "bash",
        "-c",
        `ARG_TASK_ID=${taskId} ARG_AGENTAPI_PORT=3284 ARG_PID_FILE_PATH=${pidFilePath} ARG_ENABLE_STATE_PERSISTENCE=${enableStatePersistence} CODER_AGENT_URL=http://localhost:18080 CODER_AGENT_TOKEN=test-token /tmp/shutdown.sh`,
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
      expect(result.stdout).not.toContain("Log snapshot capture failed");

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

    test("sends SIGUSR1 before shutdown", async () => {
      const { id } = await setup({
        moduleVariables: {},
        skipAgentAPIMock: true,
      });
      const pidFile = "/tmp/agentapi-test.pid";
      await setupMocks(id, "normal", 204, pidFile);
      const result = await runShutdownScript(id, "test-task", pidFile, "true");

      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain("Sending SIGUSR1 to AgentAPI");

      const sigusr1Log = await readFileContainer(id, "/tmp/sigusr1-received");
      expect(sigusr1Log).toContain("SIGUSR1 received");
    });

    test("handles missing PID file gracefully", async () => {
      const { id } = await setup({
        moduleVariables: {},
        skipAgentAPIMock: true,
      });
      await setupMocks(id, "normal");
      // Pass a non-existent PID file path with persistence enabled to
      // exercise the SIGUSR1 path with a missing PID.
      const result = await runShutdownScript(
        id,
        "test-task",
        "/tmp/nonexistent.pid",
        "true",
      );

      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain("Shutdown complete");
    });

    test("sends SIGTERM even when snapshot fails", async () => {
      const { id } = await setup({
        moduleVariables: {},
        skipAgentAPIMock: true,
      });
      const pidFile = "/tmp/agentapi-test.pid";
      // HTTP 500 will cause snapshot to fail
      await setupMocks(id, "normal", 500, pidFile);
      const result = await runShutdownScript(id, "test-task", pidFile, "true");

      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain(
        "Log snapshot capture failed, continuing shutdown",
      );
      expect(result.stdout).toContain("Sending SIGTERM to AgentAPI");
    });

    test("resolves default PID path from MODULE_DIR_NAME", async () => {
      const { id } = await setup({
        moduleVariables: {},
        skipAgentAPIMock: true,
      });
      // Start mock with PID file at the module_dir_name default location.
      const defaultPidPath = `/home/coder/${moduleDirName}/agentapi.pid`;
      await setupMocks(id, "normal", 204, defaultPidPath);
      // Don't pass pidFilePath - let shutdown script compute it from MODULE_DIR_NAME.
      const shutdownScript = await loadTestFile(
        import.meta.dir,
        "../scripts/agentapi-shutdown.sh",
      );
      const libScript = await loadTestFile(
        import.meta.dir,
        "../scripts/lib.sh",
      );
      await writeExecutable({
        containerId: id,
        filePath: "/tmp/agentapi-lib.sh",
        content: libScript,
      });
      await writeExecutable({
        containerId: id,
        filePath: "/tmp/shutdown.sh",
        content: shutdownScript,
      });
      const result = await execContainer(id, [
        "bash",
        "-c",
        `ARG_TASK_ID=test-task ARG_AGENTAPI_PORT=3284 ARG_MODULE_DIR_NAME=${moduleDirName} ARG_ENABLE_STATE_PERSISTENCE=true CODER_AGENT_URL=http://localhost:18080 CODER_AGENT_TOKEN=test-token /tmp/shutdown.sh`,
      ]);

      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain("Sending SIGUSR1 to AgentAPI");
      expect(result.stdout).toContain("Sending SIGTERM to AgentAPI");
    });

    test("skips SIGUSR1 when no PID file available", async () => {
      const { id } = await setup({
        moduleVariables: {},
        skipAgentAPIMock: true,
      });
      await setupMocks(id, "normal", 204);
      // No pidFilePath and no MODULE_DIR_NAME, so no PID file can be resolved.
      const result = await runShutdownScript(id, "test-task", "", "false");

      expect(result.exitCode).toBe(0);
      // Should not send SIGUSR1 or SIGTERM (no PID to signal).
      expect(result.stdout).not.toContain("Sending SIGUSR1");
      expect(result.stdout).not.toContain("Sending SIGTERM");
      expect(result.stdout).toContain("Shutdown complete");
    });

    test("skips SIGUSR1 when state persistence disabled", async () => {
      const { id } = await setup({
        moduleVariables: {},
        skipAgentAPIMock: true,
      });
      const pidFile = "/tmp/agentapi-test.pid";
      await setupMocks(id, "normal", 204, pidFile);
      // PID file exists but state persistence is disabled.
      const result = await runShutdownScript(id, "test-task", pidFile, "false");

      expect(result.exitCode).toBe(0);
      // Should NOT send SIGUSR1 (persistence disabled).
      expect(result.stdout).not.toContain("Sending SIGUSR1");
      // Should still send SIGTERM (graceful shutdown always happens).
      expect(result.stdout).toContain("Sending SIGTERM to AgentAPI");
    });
  });
});
