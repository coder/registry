import { expect, it } from "bun:test";
import {
  execContainer,
  findResourceInstance,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  writeFileContainer,
} from "~test";

for (const pipx of ["pipx==1.0.0", "pipx"]) {
  it(`installs notebook packages with fresh and existing ${pipx} installations`, async () => {
    await runTerraformInit(import.meta.dir);
    const id = await runContainer("python:3.12-slim");
    const env = [
      "--env",
      "PIPX_HOME=/root/custom-pipx",
      "--env",
      "PIPX_BIN_DIR=/root/custom-bin",
      "--env",
      "PATH=/root/custom-bin:/usr/local/bin:/usr/bin:/bin",
    ];
    try {
      const install = await execContainer(id, ["pip", "install", pipx]);
      expect(install.exitCode, install.stderr).toBe(0);
      await writeFileContainer(
        id,
        "/tmp/check-kernel.py",
        await Bun.file(`${import.meta.dir}/testdata/check-kernel.py`).text(),
      );

      for (const port of [20935, 20936]) {
        const state = await runTerraformApply(import.meta.dir, {
          agent_id: "foo",
          port,
          config: JSON.stringify({ ServerApp: { allow_root: true } }),
        });
        const config = findResourceInstance(
          state,
          "coder_script",
          "jupyterlab_config",
        ).script;
        const script = findResourceInstance(
          state,
          "coder_script",
          "jupyterlab",
        ).script;
        const configure = await execContainer(id, ["sh", "-c", config], env);
        expect(configure.exitCode, configure.stderr).toBe(0);
        const startup = await execContainer(id, ["sh", "-c", script], env);
        expect(startup.exitCode, startup.stderr).toBe(0);
        const probe = await execContainer(
          id,
          [
            "/root/custom-pipx/venvs/jupyterlab/bin/python",
            "/tmp/check-kernel.py",
            String(port),
          ],
          env,
        );
        expect(probe.exitCode, probe.stdout + probe.stderr).toBe(0);
        expect(probe.stdout).toContain("installed-in-kernel");
        // The second launch must install a fresh package, not reuse the first result.
        const uninstall = await execContainer(
          id,
          ["pipx", "runpip", "jupyterlab", "uninstall", "-y", "registry-probe"],
          env,
        );
        expect(uninstall.exitCode, uninstall.stderr).toBe(0);
      }
    } finally {
      await removeContainer(id);
    }
  }, 300_000);
}
