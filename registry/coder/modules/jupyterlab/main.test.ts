import { describe, expect, it, setDefaultTimeout } from "bun:test";
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
  writeFileContainer,
} from "~test";

setDefaultTimeout(30_000);

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
      "No supported installer found.",
      "Please install pipx or uv in your Dockerfile/VM image before running this script",
    ]);
  });

  for (const installer of ["pipx", "uv"]) {
    it(`propagates ${installer} installation failures`, async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
      });
      const script = findResourceInstance(
        state,
        "coder_script",
        "jupyterlab",
      ).script;
      const id = await runContainer("alpine");
      try {
        await writeFileContainer(
          id,
          `/usr/local/bin/${installer}`,
          "#!/bin/sh\necho installer-failed >&2\nexit 42\n",
        );
        await execContainer(id, [
          "chmod",
          "755",
          `/usr/local/bin/${installer}`,
        ]);
        const result = await execContainer(id, ["sh", "-c", script]);
        expect(result.exitCode).toBe(42);
        expect(result.stderr).toContain("installer-failed");
        expect(result.stdout).not.toContain("Starting jupyterlab");
      } finally {
        await removeContainer(id);
      }
    });
  }

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

  it("binds to loopback by default without changing Coder URLs", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    const script = findResourceInstance(
      state,
      "coder_script",
      "jupyterlab",
    ).script;
    const app = findResourceInstance(state, "coder_app", "jupyterlab");

    expect(script).toContain("--ServerApp.ip='127.0.0.1'");
    expect(script).not.toContain("0.0.0.0");
    expect(script).not.toContain("--ServerApp.ip='*'");
    expect(script).toContain("--ServerApp.allow_remote_access=True");
    expect(app.url).toBe("http://localhost:19999");

    const id = await runContainer("alpine");
    try {
      await writeFileContainer(
        id,
        "/usr/local/bin/jupyter-lab",
        "#!/bin/sh\nprintf '%s\\n' \"$@\" > /tmp/jupyter-args\n",
      );
      await execContainer(id, ["chmod", "755", "/usr/local/bin/jupyter-lab"]);
      const result = await execContainer(id, ["sh", "-c", script]);
      expect(result.exitCode).toBe(0);
      const args = await readFileContainer(id, "/tmp/jupyter-args");
      expect(args).toContain("--ServerApp.ip=127.0.0.1");
      expect(args).toContain("--ServerApp.allow_remote_access=True");
    } finally {
      await removeContainer(id);
    }
  });

  it("preserves path mode and renders an explicit external host", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      host: "0.0.0.0",
      subdomain: false,
    });
    const script = findResourceInstance(
      state,
      "coder_script",
      "jupyterlab",
    ).script;

    expect(script).toContain("--ServerApp.ip='0.0.0.0'");
    expect(script).toContain("--ServerApp.allow_remote_access=True");
    expect(script).toContain("--ServerApp.base_url=/@");
    expect(script).toContain("/apps/jupyterlab");
  });

  for (const unsafeHost of [
    "127.0.0.1; touch /tmp/injected",
    "127.0.0.1 $(id)",
    "127.0.0.1`id`",
    "127.0.0.1'quoted",
  ]) {
    it(`rejects unsafe host ${JSON.stringify(unsafeHost)}`, async () => {
      const apply = runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        host: unsafeHost,
      });
      await expect(apply).rejects.toThrow("host must contain only");
    });
  }
});
