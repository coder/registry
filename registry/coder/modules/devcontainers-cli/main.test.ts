import { describe, expect, it, setDefaultTimeout } from "bun:test";
import {
  execContainer,
  findResourceInstance,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";
import {
  SCRIPT_BIN_DIR,
  SCRIPT_DATA_DIR,
  executeInAlpine,
  packageManagerStub,
  setupPackageManager,
  writeExecutable,
} from "./test-util";

setDefaultTimeout(120 * 1000);

describe("devcontainers-cli", async () => {
  await runTerraformInit(import.meta.dir);

  const defaultState = await runTerraformApply(import.meta.dir, {
    agent_id: "some-agent-id",
  });

  testRequiredVariables(import.meta.dir, {
    agent_id: "some-agent-id",
  });

  it("skips installation when devcontainer is already available", async () => {
    const output = await executeInAlpine(defaultState, async (containerID) => {
      await writeExecutable(
        containerID,
        "/usr/local/bin/devcontainer",
        "#!/bin/sh\nexit 0\n",
      );
    });

    expect(output.exitCode).toBe(0);
    expect(output.stdout).toEqual([
      "🥳 @devcontainers/cli is already installed into /usr/local/bin/devcontainer!",
    ]);
  });

  it("fails when no supported package manager is available", async () => {
    const output = await executeInAlpine(defaultState, async (containerID) => {
      await writeExecutable(
        containerID,
        "/usr/local/bin/docker",
        "#!/bin/sh\nexit 0\n",
      );
    });

    expect(output.exitCode).toBe(1);
    expect(output.stderr).toEqual([
      "ERROR: No supported package manager (npm, pnpm, yarn) is installed. Please install one first.",
    ]);
  });

  it("warns when Docker is unavailable without blocking installation", async () => {
    const output = await executeInAlpine(defaultState, async (containerID) => {
      await writeExecutable(
        containerID,
        "/usr/local/bin/npm",
        packageManagerStub(),
      );
    });

    expect(output.exitCode).toBe(0);
    expect(output.stdout[0]).toBe(
      "WARNING: Docker was not found but is required to use @devcontainers/cli, please make sure it is available.",
    );
    expect(output.stdout.at(-1)).toBe(
      `🥳 @devcontainers/cli has been installed into ${SCRIPT_BIN_DIR}/devcontainer!`,
    );
  });

  it("passes the configured version and registry to every package manager", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "some-agent-id",
      devcontainers_cli_version: "0.80.0",
      registry_url: "https://registry.example.com/npm",
    });
    const cases = [
      [
        "npm",
        [
          "install",
          "--global",
          "@devcontainers/cli@0.80.0",
          "--prefix",
          SCRIPT_DATA_DIR,
        ],
      ],
      ["pnpm", ["add", "--global", "@devcontainers/cli@0.80.0"]],
      [
        "yarn",
        [
          "global",
          "add",
          "@devcontainers/cli@0.80.0",
          "--prefix",
          SCRIPT_DATA_DIR,
        ],
      ],
    ] as const;

    for (const [packageManager, expectedArgs] of cases) {
      const output = await executeInAlpine(state, async (containerID) => {
        await setupPackageManager(containerID, packageManager);
      });

      expect(output.exitCode).toBe(0);
      expect(output.packageManagerArgs).toEqual([
        ...expectedArgs,
        "--registry",
        "https://registry.example.com/npm",
      ]);
    }
  });

  it("preserves package-manager failures", async () => {
    const output = await executeInAlpine(defaultState, async (containerID) => {
      await setupPackageManager(
        containerID,
        "npm",
        packageManagerStub(17, false),
      );
    });

    expect(output.exitCode).toBe(17);
    expect(output.stderr).toEqual(["Failed to install @devcontainers/cli"]);
  });

  it("fails when installation does not expose devcontainer on PATH", async () => {
    const output = await executeInAlpine(defaultState, async (containerID) => {
      await setupPackageManager(
        containerID,
        "npm",
        packageManagerStub(0, false),
      );
    });

    expect(output.exitCode).toBe(1);
    expect(output.stderr).toEqual([
      "Installation completed but 'devcontainer' command not found in PATH",
    ]);
  });

  it("installs and runs a pinned devcontainers CLI with npm", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "some-agent-id",
      devcontainers_cli_version: "0.80.0",
    });
    const instance = findResourceInstance(state, "coder_script");
    const containerID = await runContainer("node:22-alpine");
    const path = `/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${SCRIPT_BIN_DIR}`;
    const env = [
      "--env",
      `CODER_SCRIPT_DATA_DIR=${SCRIPT_DATA_DIR}`,
      "--env",
      `CODER_SCRIPT_BIN_DIR=${SCRIPT_BIN_DIR}`,
      "--env",
      `PATH=${path}`,
    ];

    try {
      await execContainer(containerID, ["mkdir", "-p", SCRIPT_BIN_DIR]);
      const install = await execContainer(
        containerID,
        ["sh", "-c", instance.script],
        env,
      );
      expect(install.exitCode).toBe(0);

      const version = await execContainer(
        containerID,
        ["devcontainer", "--version"],
        env,
      );
      expect(version.exitCode).toBe(0);
      expect(version.stdout.trim()).toBe("0.80.0");
    } finally {
      await removeContainer(containerID);
    }
  });
});
