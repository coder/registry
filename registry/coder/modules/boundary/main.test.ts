import {
  test,
  afterEach,
  describe,
  setDefaultTimeout,
  beforeAll,
  expect,
} from "bun:test";
import {
  execContainer,
  readFileContainer,
  runTerraformInit,
  runTerraformApply,
  testRequiredVariables,
  runContainer,
  removeContainer,
} from "~test";
import {
  loadTestFile,
  writeExecutable,
  execModuleScript,
  extractCoderEnvVars,
} from "../agentapi/test-util";

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
  moduleVariables?: Record<string, string>;
  skipCoderMock?: boolean;
}

const setup = async (
  props?: SetupProps,
): Promise<{ id: string; coderEnvVars: Record<string, string> }> => {
  const state = await runTerraformApply(import.meta.dir, {
    agent_id: "foo",
    ...props?.moduleVariables,
  });

  const coderEnvVars = extractCoderEnvVars(state);
  const id = await runContainer("codercom/enterprise-node:latest");
  registerCleanup(async () => {
    await removeContainer(id);
  });

  await execContainer(id, ["bash", "-c", "mkdir -p /home/coder/project"]);

  // Create a mock coder binary with boundary subcommand and exp sync support
  if (!props?.skipCoderMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/coder",
      content: await loadTestFile(import.meta.dir, "coder-mock.sh"),
    });
  }

  // Extract ALL coder_scripts from the state (coder-utils creates multiple)
  const allScripts = state.resources
    .filter((r) => r.type === "coder_script")
    .map((r) => ({
      name: r.name,
      script: r.instances[0].attributes.script as string,
    }));

  // Run scripts in lifecycle order
  const executionOrder = [
    "pre_install_script",
    "install_script",
    "post_install_script",
  ];
  const orderedScripts = executionOrder
    .map((name) => allScripts.find((s) => s.name === name))
    .filter((s): s is NonNullable<typeof s> => s != null);

  // Write each script individually and create a combined runner
  const scriptPaths: string[] = [];
  for (const s of orderedScripts) {
    const scriptPath = `/home/coder/${s.name}.sh`;
    await writeExecutable({
      containerId: id,
      filePath: scriptPath,
      content: s.script,
    });
    scriptPaths.push(scriptPath);
  }

  const combinedScript = [
    "#!/bin/bash",
    "set -o errexit",
    "set -o pipefail",
    ...scriptPaths.map((p) => `bash "${p}"`),
  ].join("\n");

  await writeExecutable({
    containerId: id,
    filePath: "/home/coder/script.sh",
    content: combinedScript,
  });

  return { id, coderEnvVars };
};

setDefaultTimeout(60 * 1000);

describe("boundary", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  testRequiredVariables(import.meta.dir, {
    agent_id: "test-agent-id",
  });

  test("terraform-state-basic", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent-id",
    });

    const resources = state.resources;

    // Verify coder_env resource for BOUNDARY_WRAPPER_PATH
    const boundaryEnv = resources.find(
      (r) => r.type === "coder_env" && r.name === "boundary_wrapper_path",
    );
    expect(boundaryEnv).toBeDefined();
    expect(boundaryEnv?.instances[0]?.attributes.name).toBe(
      "BOUNDARY_WRAPPER_PATH",
    );
    expect(boundaryEnv?.instances[0]?.attributes.value).toBe(
      "$HOME/.coder-modules/coder/boundary/scripts/boundary-wrapper.sh",
    );

    // Verify coder_env resource for BOUNDARY_CONFIG
    const configEnv = resources.find(
      (r) => r.type === "coder_env" && r.name === "boundary_config",
    );
    expect(configEnv).toBeDefined();
    expect(configEnv?.instances[0]?.attributes.name).toBe("BOUNDARY_CONFIG");
    expect(configEnv?.instances[0]?.attributes.value).toBe(
      "$HOME/.config/coder_boundary/config.yaml",
    );

    // Verify the outputs are set correctly
    const coderEnvVars = extractCoderEnvVars(state);
    expect(coderEnvVars["BOUNDARY_WRAPPER_PATH"]).toBe(
      "$HOME/.coder-modules/coder/boundary/scripts/boundary-wrapper.sh",
    );
    expect(coderEnvVars["BOUNDARY_CONFIG"]).toBe(
      "$HOME/.config/coder_boundary/config.yaml",
    );
  });

  test("terraform-state-custom-module-directory", async () => {
    const customDir = "$HOME/.coder-modules/custom/boundary";
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent-id",
      module_directory: customDir,
    });

    const coderEnvVars = extractCoderEnvVars(state);
    expect(coderEnvVars["BOUNDARY_WRAPPER_PATH"]).toBe(
      `${customDir}/scripts/boundary-wrapper.sh`,
    );
  });

  test("terraform-state-inline-config", async () => {
    const inlineConfig =
      "allowlist:\n  - domain=example.com\nlog_level: debug\n";
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent-id",
      boundary_config: inlineConfig,
    });

    const coderEnvVars = extractCoderEnvVars(state);
    // Inline config still writes to the managed path.
    expect(coderEnvVars["BOUNDARY_CONFIG"]).toBe(
      "$HOME/.config/coder_boundary/config.yaml",
    );
  });

  test("terraform-state-config-path", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent-id",
      boundary_config_path: "/workspace/my-config.yaml",
    });

    const coderEnvVars = extractCoderEnvVars(state);
    // BOUNDARY_CONFIG should point to the user-provided path.
    expect(coderEnvVars["BOUNDARY_CONFIG"]).toBe("/workspace/my-config.yaml");
  });

  test("happy-path-coder-subcommand", async () => {
    const { id } = await setup();
    await execModuleScript(id);

    // Verify the wrapper script was created
    const wrapperContent = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder/boundary/scripts/boundary-wrapper.sh",
    );
    expect(wrapperContent).toContain("#!/usr/bin/env bash");
    expect(wrapperContent).toContain("coder-no-caps");
    expect(wrapperContent).toContain("boundary");

    // Verify the wrapper script is executable
    const statResult = await execContainer(id, [
      "stat",
      "-c",
      "%a",
      "/home/coder/.coder-modules/coder/boundary/scripts/boundary-wrapper.sh",
    ]);
    expect(statResult.stdout.trim()).toMatch(/7[0-9][0-9]/); // Should be executable (7xx)

    // Verify coder-no-caps binary was created
    const coderNoCapsResult = await execContainer(id, [
      "test",
      "-f",
      "/home/coder/.coder-modules/coder/boundary/scripts/coder-no-caps",
    ]);
    expect(coderNoCapsResult.exitCode).toBe(0);

    // Verify default boundary config was written
    const configContent = await readFileContainer(
      id,
      "/home/coder/.config/coder_boundary/config.yaml",
    );
    expect(configContent).toContain("allowlist:");
    expect(configContent).toContain("domain=api.anthropic.com");
    expect(configContent).toContain("proxy_port: 8087");

    // Check install log
    const installLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder/boundary/logs/install.log",
    );
    expect(installLog).toContain("Using coder boundary subcommand");
    expect(installLog).toContain("Boundary config written to");
    expect(installLog).toContain("boundary wrapper configured");
  });

  test("inline-config-written", async () => {
    const customConfig =
      "allowlist:\n  - domain=custom.example.com\nlog_level: info\n";
    const { id } = await setup({
      moduleVariables: {
        boundary_config: customConfig,
      },
    });
    await execModuleScript(id);

    // Verify the inline config was written
    const configContent = await readFileContainer(
      id,
      "/home/coder/.config/coder_boundary/config.yaml",
    );
    expect(configContent).toContain("domain=custom.example.com");
    expect(configContent).toContain("log_level: info");
  });

  test("config-path-skips-write", async () => {
    const { id } = await setup({
      moduleVariables: {
        boundary_config_path: "/workspace/external-config.yaml",
      },
    });
    await execModuleScript(id);

    // Verify NO config was written to the default path
    const checkResult = await execContainer(id, [
      "test",
      "-f",
      "/home/coder/.config/coder_boundary/config.yaml",
    ]);
    expect(checkResult.exitCode).not.toBe(0);

    // Check install log confirms skip
    const installLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder/boundary/logs/install.log",
    );
    expect(installLog).toContain(
      "Using external boundary config, skipping config write",
    );
  });

  // Note: Tests for use_boundary_directly and compile_from_source are skipped
  // because they require network access (downloading boundary) or compilation
  // which are too slow for unit tests. These modes are tested manually.

  test("custom-hooks", async () => {
    const preInstallMarker = "pre-install-executed";
    const postInstallMarker = "post-install-executed";

    const { id } = await setup({
      moduleVariables: {
        pre_install_script: `#!/bin/bash\necho '${preInstallMarker}'`,
        post_install_script: `#!/bin/bash\necho '${postInstallMarker}'`,
      },
    });
    await execModuleScript(id);

    // Verify pre-install script ran
    const preInstallLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder/boundary/logs/pre_install.log",
    );
    expect(preInstallLog).toContain(preInstallMarker);

    // Verify post-install script ran
    const postInstallLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder/boundary/logs/post_install.log",
    );
    expect(postInstallLog).toContain(postInstallMarker);

    // Verify main install still ran
    const installLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder/boundary/logs/install.log",
    );
    expect(installLog).toContain("boundary wrapper configured");
  });

  test("env-var-set-correctly", async () => {
    const { id, coderEnvVars } = await setup();

    // Verify BOUNDARY_WRAPPER_PATH is in the coder env vars
    expect(coderEnvVars["BOUNDARY_WRAPPER_PATH"]).toBe(
      "$HOME/.coder-modules/coder/boundary/scripts/boundary-wrapper.sh",
    );

    // Verify BOUNDARY_CONFIG is in the coder env vars
    expect(coderEnvVars["BOUNDARY_CONFIG"]).toBe(
      "$HOME/.config/coder_boundary/config.yaml",
    );
  });

  test("wrapper-script-execution", async () => {
    const { id } = await setup();
    await execModuleScript(id);

    // Try executing the wrapper script with a command
    const wrapperResult = await execContainer(id, [
      "bash",
      "-c",
      "/home/coder/.coder-modules/coder/boundary/scripts/boundary-wrapper.sh echo boundary-test",
    ]);

    // The wrapper passes the command directly to the boundary command
    expect(wrapperResult.stdout).toContain("boundary-test");
  });

  test("installation-idempotency", async () => {
    const { id } = await setup();

    // Run the installation twice
    await execModuleScript(id);
    const firstInstallLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder/boundary/logs/install.log",
    );

    // Run again
    const secondRun = await execModuleScript(id);
    expect(secondRun.exitCode).toBe(0);

    // Both runs should succeed
    expect(firstInstallLog).toContain("boundary wrapper configured");
  });
});
