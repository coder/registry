import { describe, expect, it } from "bun:test";
import {
  execContainer,
  executeScriptInContainer,
  findResourceInstance,
  readFileContainer,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  type TerraformState,
} from "~test";

// executes the coder script after installing pip
const executeScriptInContainerWithPip = async (
  state: TerraformState,
  image: string,
  shell = "sh",
): Promise<{
  exitCode: number;
  stdout: string[];
  stderr: string[];
}> => {
  const instance = findResourceInstance(state, "coder_script");
  const id = await runContainer(image);
  const respPipx = await execContainer(id, [shell, "-c", "apk add pipx"]);
  const resp = await execContainer(id, [shell, "-c", instance.script]);
  const stdout = resp.stdout.trim().split("\n");
  const stderr = resp.stderr.trim().split("\n");
  return {
    exitCode: resp.exitCode,
    stdout,
    stderr,
  };
};

// executes the coder script after installing pip
const executeScriptInContainerWithUv = async (
  state: TerraformState,
  image: string,
  shell = "sh",
): Promise<{
  exitCode: number;
  stdout: string[];
  stderr: string[];
}> => {
  const instance = findResourceInstance(state, "coder_script");
  const id = await runContainer(image);
  const respPipx = await execContainer(id, [
    shell,
    "-c",
    "apk --no-cache add uv gcc musl-dev linux-headers && uv venv",
  ]);
  const resp = await execContainer(id, [shell, "-c", instance.script]);
  const stdout = resp.stdout.trim().split("\n");
  const stderr = resp.stderr.trim().split("\n");
  return {
    exitCode: resp.exitCode,
    stdout,
    stderr,
  };
};

describe("jupyterlab", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("fails without installers", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    const output = await executeScriptInContainer(state, "alpine");
    expect(output.exitCode).toBe(1);
    expect(output.stdout).toEqual([
      "Checking for a supported installer",
      "No valid installer is not installed",
      "Please install pipx or uv in your Dockerfile/VM image before running this script",
    ]);
  });

  // TODO: Add faster test to run with uv.
  // currently times out.
  // it("runs with uv", async () => {
  //   const state = await runTerraformApply(import.meta.dir, {
  //     agent_id: "foo",
  //   });
  //   const output = await executeScriptInContainerWithUv(state, "python:3-alpine");
  //   expect(output.exitCode).toBe(0);
  //   expect(output.stdout).toEqual([
  //     "Checking for a supported installer",
  //     "uv is installed",
  //     "\u001B[0;1mInstalling jupyterlab!",
  //     "🥳 jupyterlab has been installed",
  //     "👷 Starting jupyterlab in background...check logs at /tmp/jupyterlab.log",
  //   ]);
  // });

  // TODO: Add faster test to run with pipx.
  // currently times out.
  // it("runs with pipx", async () => {
  //   ...
  //   const output = await executeScriptInContainerWithPip(state, "alpine");
  //   ...
  // });

  it("writes ~/.jupyter/jupyter_server_config.json when config provided", async () => {
    const id = await runContainer("alpine");
    try {
      const config = {
        ServerApp: {
          port: 8888,
          token: "test-token",
          password: "",
          allow_origin: "*",
        },
      };
      const configJson = JSON.stringify(config);
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        config: configJson,
      });
      const script = findResourceInstance(
        state,
        "coder_script",
        "jupyterlab_config",
      ).script;
      const resp = await execContainer(id, ["sh", "-c", script]);
      if (resp.exitCode !== 0) {
        console.log(resp.stdout);
        console.log(resp.stderr);
      }
      expect(resp.exitCode).toBe(0);
      const content = await readFileContainer(
        id,
        "/root/.jupyter/jupyter_server_config.json",
      );
      // Parse both JSON strings and compare objects to avoid key ordering issues
      const actualConfig = JSON.parse(content);
      expect(actualConfig).toEqual(config);
    } finally {
      await removeContainer(id);
    }
  });

  it("creates config script with CSP fallback when config is empty", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      config: "{}",
    });
    const configScripts = state.resources.filter(
      (res) => res.type === "coder_script" && res.name === "jupyterlab_config",
    );
    expect(configScripts.length).toBe(1);
  });

  it("creates config script with CSP fallback when config is not provided", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    const configScripts = state.resources.filter(
      (res) => res.type === "coder_script" && res.name === "jupyterlab_config",
    );
    expect(configScripts.length).toBe(1);
  });
});
