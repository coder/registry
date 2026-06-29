import { describe, expect, it, setDefaultTimeout } from "bun:test";
import {
  execContainer,
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

describe("jupyter-notebook", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("binds to loopback by default", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    const script = findResourceInstance(state, "coder_script").script;

    expect(script).toContain("--NotebookApp.ip='127.0.0.1'");
    expect(script).not.toContain("0.0.0.0");
    expect(script).not.toContain("--NotebookApp.ip='*'");
    expect(script).not.toContain("--ServerApp.ip='*'");

    const id = await runContainer("alpine");
    try {
      await execContainer(id, ["mkdir", "-p", "/root/.local/bin"]);
      await writeFileContainer(
        id,
        "/root/.local/bin/jupyter-notebook",
        "#!/bin/sh\nprintf '%s\\n' \"$@\" > /tmp/jupyter-args\n",
      );
      await execContainer(id, [
        "chmod",
        "755",
        "/root/.local/bin/jupyter-notebook",
      ]);
      const result = await execContainer(
        id,
        ["sh", "-c", script],
        [
          "--env",
          "PATH=/root/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin",
        ],
      );
      expect(result.exitCode).toBe(0);
      const args = await readFileContainer(id, "/tmp/jupyter-args");
      expect(args).toContain("--NotebookApp.ip=127.0.0.1");
    } finally {
      await removeContainer(id);
    }
  });

  it("renders an explicit external host", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      host: "0.0.0.0",
    });
    const script = findResourceInstance(state, "coder_script").script;
    expect(script).toContain("--NotebookApp.ip='0.0.0.0'");
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
