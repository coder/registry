import { describe, expect, it } from "bun:test";
import { chmod, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import {
  findResourceInstance,
  runTerraformApply,
  runTerraformInit,
} from "~test";

const run = async (cmd: string[], env?: Record<string, string>) => {
  const proc = Bun.spawn(cmd, {
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env, ...env },
  });
  const [exitCode, stdout, stderr] = await Promise.all([
    proc.exited,
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  if (exitCode !== 0) {
    console.error(stdout, stderr);
  }
  return { exitCode, stdout, stderr };
};

describe("nix", async () => {
  await runTerraformInit(import.meta.dir);

  it("lifecycle library passes its shell tests", async () => {
    const { exitCode, stdout } = await run([
      "bash",
      path.join(import.meta.dir, "scripts", "lifecycle.test.sh"),
    ]);
    expect(exitCode).toBe(0);
    expect(stdout).toContain("lifecycle tests passed");
  });

  it("nix develop app enters the project and runs nix develop", async () => {
    const home = await mkdtemp(path.join(tmpdir(), "nix-develop-"));
    try {
      // A project path with a space and a quote exercises shell quoting.
      const project = "my 'project";
      await mkdir(path.join(home, project));
      const bin = path.join(home, "bin");
      await mkdir(bin);
      // Stub nix: record the working directory and arguments.
      await writeFile(
        path.join(bin, "nix"),
        '#!/usr/bin/env bash\nprintf "%s\\n" "$PWD" "$@"\n',
      );
      await chmod(path.join(bin, "nix"), 0o755);

      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        nixos: JSON.stringify({ enabled: false }),
        develop: JSON.stringify({
          enabled: true,
          path: `~/${project}`,
          shell: "ci",
        }),
      });
      const app = findResourceInstance(state, "coder_app", "develop");
      expect(app.slug).toBe("nix-develop");

      const { exitCode, stdout } = await run(["bash", "-c", app.command], {
        HOME: home,
        PATH: `${bin}:${process.env.PATH}`,
      });
      expect(exitCode).toBe(0);
      expect(stdout.trimEnd().split("\n")).toEqual([
        path.join(home, project),
        "--extra-experimental-features",
        "nix-command flakes",
        "develop",
        ".#ci",
      ]);
    } finally {
      await rm(home, { recursive: true, force: true });
    }
  });
});
