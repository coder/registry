import { describe, expect, it } from "bun:test";
import {
  execContainer,
  executeScriptInContainer,
  findResourceInstance,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  type TerraformState,
} from "~test";

const executeScriptInContainerWithPackageManager = async (
  state: TerraformState,
  image: string,
  packageManager: string,
  shell = "sh",
): Promise<{
  exitCode: number;
  stdout: string[];
  stderr: string[];
}> => {
  const instance = findResourceInstance(state, "coder_script");
  const id = await runContainer(image);

  // Install the specified package manager
  if (packageManager === "npm") {
    await execContainer(id, [shell, "-c", "apk add nodejs npm"]);
  } else if (packageManager === "pnpm") {
    await execContainer(id, [
      shell,
      "-c",
      `wget -qO- https://get.pnpm.io/install.sh | ENV="$HOME/.shrc" SHELL="$(which sh)" sh -`,
    ]);
  } else if (packageManager === "yarn") {
    await execContainer(id, [
      shell,
      "-c",
      "apk add nodejs npm && npm install -g yarn",
    ]);
  }

  const pathResp = await execContainer(id, [shell, "-c", "echo $PATH"]);
  const path = pathResp.stdout.trim();

  console.log(path);

  await execContainer(id, [shell, "-c", "mkdir -p /tmp/coder-script-data"]);

  const resp = await execContainer(
    id,
    [shell, "-c", instance.script],
    [
      "--env",
      "CODER_SCRIPT_BIN_DIR=/tmp/coder-script-data/bin",
      "--env",
      "CODER_SCRIPT_DATA_DIR=/tmp/coder-script-data",
      "--env",
      `PATH=${path}:/tmp/coder-script-data/bin`,
    ],
  );
  const stdout = resp.stdout.trim().split("\n");
  const stderr = resp.stderr.trim().split("\n");
  return {
    exitCode: resp.exitCode,
    stdout,
    stderr,
  };
};

describe("devcontainers-cli", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "some-agent-id",
  });

  it("misses all package managers", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "some-agent-id",
    });
    const output = await executeScriptInContainer(state, "docker:dind");
    expect(output.exitCode).toBe(1);
    expect(output.stderr).toEqual([
      "ERROR: No supported package manager (npm, pnpm, yarn) is installed. Please install one first.",
    ]);
  }, 15000);

  it("installs devcontainers-cli with npm", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "some-agent-id",
    });

    const output = await executeScriptInContainerWithPackageManager(
      state,
      "docker:dind",
      "npm",
    );
    expect(output.exitCode).toBe(0);

    expect(output.stdout[0]).toEqual(
      "Installing @devcontainers/cli using npm...",
    );
    expect(output.stdout[output.stdout.length - 1]).toEqual(
      "🥳 @devcontainers/cli has been installed into /usr/local/bin/devcontainer!",
    );
  }, 15000);

  it("installs devcontainers-cli with yarn", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "some-agent-id",
    });

    const output = await executeScriptInContainerWithPackageManager(
      state,
      "docker:dind",
      "yarn",
    );
    expect(output.exitCode).toBe(0);

    expect(output.stdout[0]).toEqual(
      "Installing @devcontainers/cli using yarn...",
    );
    expect(output.stdout[output.stdout.length - 1]).toEqual(
      "🥳 @devcontainers/cli has been installed into /tmp/coder-script-data/bin/devcontainer!",
    );
  }, 15000);

  it("displays warning if docker is not installed", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "some-agent-id",
    });

    const output = await executeScriptInContainerWithPackageManager(
      state,
      "alpine",
      "npm",
    );
    expect(output.exitCode).toBe(0);

    expect(output.stdout[0]).toEqual(
      "WARNING: Docker was not found but is required to use @devcontainers/cli, please make sure it is available.",
    );
    expect(output.stdout[output.stdout.length - 1]).toEqual(
      "🥳 @devcontainers/cli has been installed into /usr/local/bin/devcontainer!",
    );
  }, 15000);
});
