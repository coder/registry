import { describe, expect, it } from "bun:test";
import {
  execContainer,
  findResourceInstance,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("code-server", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("use_cached and offline can not be used together", () => {
    const t = async () => {
      await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        use_cached: "true",
        offline: "true",
      });
    };
    expect(t).toThrow("Offline and Use Cached can not be used together");
  });

  it("offline and extensions can not be used together", () => {
    const t = async () => {
      await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        offline: "true",
        extensions: '["1", "2"]',
      });
    };
    expect(t).toThrow("Offline mode does not allow extensions to be installed");
  });

  it("installs and runs code-server", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });

    const id = await runContainer("ubuntu:latest");
    try {
      await execContainer(id, [
        "bash",
        "-c",
        "apt-get update && apt-get install -y curl",
      ]);

      const script = findResourceInstance(state, "coder_script").script;
      const result = await execContainer(id, ["bash", "-c", script]);
      if (result.exitCode !== 0) {
        console.log(result.stdout);
        console.log(result.stderr);
      }
      expect(result.exitCode).toBe(0);

      const version = await execContainer(id, [
        "/tmp/code-server/bin/code-server",
        "--version",
      ]);
      expect(version.exitCode).toBe(0);
      expect(version.stdout).toMatch(/\d+\.\d+\.\d+/);

      const health = await execContainer(id, [
        "curl",
        "--retry",
        "10",
        "--retry-delay",
        "1",
        "--retry-all-errors",
        "-sf",
        "http://localhost:13337/healthz",
      ]);
      expect(health.exitCode).toBe(0);
    } finally {
      await removeContainer(id);
    }
  }, 60000);
});
