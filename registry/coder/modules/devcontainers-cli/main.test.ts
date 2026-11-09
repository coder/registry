import { describe, expect, it, setDefaultTimeout } from "bun:test";
import {
  execContainer,
  findResourceInstance,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  writeFileContainer,
} from "~test";
import {
  SCRIPT_BIN_DIR,
  SCRIPT_DATA_DIR,
  executeInstall,
  packageManagerStub,
  setupPackageManager,
  writeExecutable,
  mockCoderSync,
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
    const output = await executeInstall(defaultState, async (containerID) => {
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
    const output = await executeInstall(defaultState, async (containerID) => {
      await writeExecutable(
        containerID,
        "/usr/local/bin/docker",
        "#!/bin/sh\nexit 0\n",
      );
    });

    expect(output.exitCode).toBe(1);
    expect(output.stdout).toContain(
      "ERROR: No supported package manager (npm, pnpm, yarn) is installed. Please install one first.",
    );
  });

  it("warns when Docker is unavailable without blocking installation", async () => {
    const output = await executeInstall(defaultState, async (containerID) => {
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

  it("passes the pinned version without overriding package-manager registries", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "some-agent-id",
      devcontainers_cli_version: "v0.80.0",
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
      const output = await executeInstall(state, async (containerID) => {
        await setupPackageManager(containerID, packageManager);
      });

      expect(output.exitCode).toBe(0);
      expect(output.packageManagerArgs).toEqual([...expectedArgs]);
    }
  });

  it("preserves package-manager failures", async () => {
    const output = await executeInstall(defaultState, async (containerID) => {
      await setupPackageManager(
        containerID,
        "npm",
        packageManagerStub(17, false),
      );
    });

    expect(output.exitCode).toBe(17);
    expect(output.stdout).toContain("Failed to install @devcontainers/cli");
  });

  it("fails when installation does not expose devcontainer on PATH", async () => {
    const output = await executeInstall(defaultState, async (containerID) => {
      await setupPackageManager(
        containerID,
        "npm",
        packageManagerStub(0, false),
      );
    });

    expect(output.exitCode).toBe(1);
    expect(output.stdout).toContain(
      "Installation completed but 'devcontainer' command not found in PATH",
    );
  });

  it.each([0, 23])(
    "preserves the login wait and sync failures (%i)",
    async (exitCode) => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "some-agent-id",
        start_blocks_login: true,
      });
      const waiter = findResourceInstance(
        state,
        "coder_script",
        "wait_for_install",
      );
      const containerID = await runContainer("python:3.12-slim");
      try {
        await writeExecutable(
          containerID,
          "/usr/local/bin/coder",
          `#!/bin/sh
printf '%s\\n' "$*" >> /tmp/sync-calls
if [ "$3" = start ]; then exit ${exitCode}; fi
`,
        );
        const result = await execContainer(containerID, [
          "bash",
          "-c",
          waiter.script,
        ]);
        expect(result.exitCode).toBe(exitCode);
        const calls = await execContainer(containerID, [
          "cat",
          "/tmp/sync-calls",
        ]);
        expect(calls.stdout.trim().split("\n")).toEqual([
          "exp sync want coder-devcontainers-cli-login coder-devcontainers-cli-install_script",
          "exp sync start coder-devcontainers-cli-login",
          "exp sync complete coder-devcontainers-cli-login",
        ]);
      } finally {
        await removeContainer(containerID);
      }
    },
  );

  it("uses npm registry configuration to install and run a pinned CLI", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "some-agent-id",
      devcontainers_cli_version: "v0.80.0",
    });
    const instance = findResourceInstance(
      state,
      "coder_script",
      "install_script",
    );
    const containerID = await runContainer("node:22-bookworm-slim");
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
      await mockCoderSync(containerID);
      await execContainer(containerID, [
        "rm",
        "-f",
        "/usr/local/bin/yarn",
        "/usr/local/bin/yarnpkg",
      ]);
      const npmrc = "registry=http://127.0.0.1:9/\nfetch-retries=0\n";
      await writeFileContainer(containerID, "/root/.npmrc", npmrc);
      const unavailableRegistry = await execContainer(
        containerID,
        ["bash", "-c", instance.script],
        env,
      );
      expect(unavailableRegistry.exitCode).not.toBe(0);
      expect(unavailableRegistry.stdout).toContain("127.0.0.1:9");
      const config = await execContainer(containerID, ["cat", "/root/.npmrc"]);
      expect(config.stdout).toBe(npmrc);

      await writeFileContainer(
        containerID,
        "/root/.npmrc",
        "registry=https://registry.npmjs.org/\n",
      );
      const install = await execContainer(
        containerID,
        ["bash", "-c", instance.script],
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
