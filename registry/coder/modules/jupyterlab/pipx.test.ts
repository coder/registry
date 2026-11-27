import { expect, it } from "bun:test";
import {
  execContainer,
  findResourceInstance,
  readFileContainer,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  writeFileContainer,
} from "~test";

for (const scenario of [
  {
    name: "warns and starts when pip injection fails",
    managed: true,
    pip: false,
  },
  {
    name: "reuses existing pip without invoking pipx",
    managed: true,
    pip: true,
  },
  { name: "leaves non-pipx installations alone", managed: false, pip: false },
]) {
  it(scenario.name, async () => {
    await runTerraformInit(import.meta.dir);
    const state = await runTerraformApply(import.meta.dir, { agent_id: "foo" });
    const script = findResourceInstance(
      state,
      "coder_script",
      "jupyterlab",
    ).script;
    const id = await runContainer("alpine");
    const bin = "/root/custom-pipx/venvs/jupyterlab/bin";
    try {
      const setup = await execContainer(id, ["mkdir", "-p", bin]);
      expect(setup.exitCode, setup.stderr).toBe(0);
      await writeFileContainer(
        id,
        `${bin}/jupyter-lab`,
        '#!/bin/sh\nprintf "%s\\n" "$PATH" > /tmp/started-path\n',
      );
      await writeFileContainer(
        id,
        "/usr/local/bin/pipx",
        scenario.managed && !scenario.pip
          ? '#!/bin/sh\nif [ "$1" = environment ]; then echo /root/custom-pipx/venvs; exit 0; fi\necho "pipx-failed: $*" >&2\nexit 42\n'
          : '#!/bin/sh\necho "pipx-failed: $*" >&2\nexit 42\n',
      );
      if (scenario.managed) {
        await writeFileContainer(id, `${bin}/../pipx_metadata.json`, "{}");
      }
      if (scenario.pip) {
        await writeFileContainer(id, `${bin}/pip`, "#!/bin/sh\nexit 0\n");
      }
      const prepare = await execContainer(id, [
        "sh",
        "-c",
        `chmod +x ${bin}/* /usr/local/bin/pipx && ln -s ${bin}/jupyter-lab /usr/local/bin/jupyter-lab`,
      ]);
      expect(prepare.exitCode, prepare.stderr).toBe(0);
      const result = await execContainer(id, ["sh", "-c", `${script}\nwait`]);
      expect(result.exitCode, result.stderr).toBe(0);
      const path = await readFileContainer(id, "/tmp/started-path");
      expect(path.startsWith(`${bin}:`)).toBe(scenario.pip);
      if (scenario.managed && !scenario.pip) {
        expect(result.stderr).toContain("pipx-failed: inject jupyterlab pip");
        expect(result.stderr).toContain("Warning:");
      } else {
        expect(result.stderr).toBe("");
      }
    } finally {
      await removeContainer(id);
    }
  });
}
