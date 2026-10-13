import { describe, expect, it } from "bun:test";
import {
  chmod,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  writeFile,
} from "node:fs/promises";
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

// A temporary $HOME with stub `nix` and `coder` binaries. The `nix` stub
// records its working directory, NIX_CONFIG and arguments to $HOME/nix.log.
const withHome = async (fn: (home: string, bin: string) => Promise<void>) => {
  const home = await mkdtemp(path.join(tmpdir(), "nix-module-"));
  try {
    const bin = path.join(home, "bin");
    await mkdir(bin);
    await writeFile(
      path.join(bin, "nix"),
      [
        "#!/usr/bin/env bash",
        'log="$HOME/nix.log"',
        'printf "%s\\n" "$PWD" "--- NIX_CONFIG" "${NIX_CONFIG:-}" "--- ARGS" "$@" | tee "$log"',
        "",
      ].join("\n"),
    );
    await writeFile(path.join(bin, "coder"), "#!/usr/bin/env bash\nexit 0\n");
    await chmod(path.join(bin, "nix"), 0o755);
    await chmod(path.join(bin, "coder"), 0o755);
    await fn(home, bin);
  } finally {
    await rm(home, { recursive: true, force: true });
  }
};

const section = (log: string, name: string) => {
  const lines = log.trimEnd().split("\n");
  const start = lines.indexOf(`--- ${name}`) + 1;
  const end = lines.findIndex((l, i) => i >= start && l.startsWith("--- "));
  return lines.slice(start, end === -1 ? undefined : end);
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

  it("nix develop app runs under bash, enters the project with the exported NIX_CONFIG and records a profile", async () => {
    await withHome(async (home, bin) => {
      // develop.path is shell as written: quoting it is the caller's job.
      const project = "my 'project";
      await mkdir(path.join(home, project));

      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        nixos: JSON.stringify({ enabled: false }),
        config: JSON.stringify({ "keep-outputs": true }),
        develop: JSON.stringify({
          enabled: true,
          path: `"$HOME/${project}"`,
          shell: "ci",
          prebuild: false,
        }),
      });
      const app = findResourceInstance(state, "coder_app", "develop");
      expect(app.slug).toBe("nix-develop");
      // The agent exports this to every process it starts, apps included.
      const env = findResourceInstance(state, "coder_env", "nix_config");
      expect(env.name).toBe("NIX_CONFIG");

      // Coder runs a command that starts with a shebang through that
      // interpreter, regardless of the user's login shell.
      const script = path.join(home, "app.sh");
      await writeFile(script, app.command);
      await chmod(script, 0o755);
      const { exitCode, stdout } = await run([script], {
        HOME: home,
        PATH: `${bin}:${process.env.PATH}`,
        NIX_CONFIG: env.value,
      });
      expect(exitCode).toBe(0);
      expect(stdout.split("\n")[0]).toBe(path.join(home, project));
      expect(section(stdout, "NIX_CONFIG")).toEqual([
        "extra-experimental-features = nix-command flakes",
        "keep-outputs = true",
      ]);
      expect(section(stdout, "ARGS")).toEqual([
        "--extra-experimental-features",
        "nix-command flakes",
        "develop",
        "--profile",
        path.join(home, ".coder-modules/coder-labs/nix/develop/profile"),
        ".#ci",
      ]);
    });
  });

  it("nix develop app finds nix through the Nix profile script when it is not on PATH", async () => {
    await withHome(async (home, bin) => {
      await mkdir(path.join(home, "proj"));
      // Single-user installs only expose nix after sourcing this script.
      const profileDir = path.join(home, ".nix-profile/etc/profile.d");
      await mkdir(profileDir, { recursive: true });
      await writeFile(
        path.join(profileDir, "nix.sh"),
        `export PATH="${bin}:$PATH"\n`,
      );
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        nixos: JSON.stringify({ enabled: false }),
        develop: JSON.stringify({
          enabled: true,
          path: "~/proj",
          prebuild: false,
        }),
      });
      const app = findResourceInstance(state, "coder_app", "develop");
      const script = path.join(home, "app.sh");
      await writeFile(script, app.command);
      await chmod(script, 0o755);
      const { exitCode, stdout } = await run([script], {
        HOME: home,
        PATH: "/usr/bin:/bin",
      });
      expect(exitCode).toBe(0);
      expect(stdout.split("\n")[0]).toBe(path.join(home, "proj"));
      expect(section(stdout, "ARGS")).toContain("develop");
    });
  });

  it("prebuild waits for flake.nix, then builds the dev shell into a profile", async () => {
    await withHome(async (home, bin) => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        nixos: JSON.stringify({ enabled: false }),
        develop: JSON.stringify({
          enabled: true,
          path: "~/proj",
          config_override: { "extra-substituters": ["https://c.example"] },
        }),
      });
      const script = findResourceInstance(
        state,
        "coder_script",
        "install_script",
      );
      const env = findResourceInstance(state, "coder_env", "nix_config");

      // The project only appears after the script has started waiting.
      const appear = (async () => {
        await Bun.sleep(1500);
        await mkdir(path.join(home, "proj"));
        await writeFile(path.join(home, "proj", "flake.nix"), "{}\n");
      })();
      const { exitCode, stdout } = await run(["bash", "-c", script.script], {
        HOME: home,
        PATH: `${bin}:${process.env.PATH}`,
        NIX_CONFIG: env.value,
      });
      await appear;

      expect(exitCode).toBe(0);
      expect(stdout).toContain("Waiting for");
      expect(stdout).toContain("nix develop environment is ready.");
      const log = await readFile(path.join(home, "nix.log"), "utf8");
      expect(log.split("\n")[0]).toBe(path.join(home, "proj"));
      expect(section(log, "NIX_CONFIG")).toEqual([
        "extra-experimental-features = nix-command flakes",
        "extra-substituters = https://c.example",
      ]);
      expect(section(log, "ARGS")).toEqual([
        "--extra-experimental-features",
        "nix-command flakes",
        "develop",
        "--profile",
        path.join(home, ".coder-modules/coder-labs/nix/develop/profile"),
        ".",
        "--command",
        "true",
      ]);
      // coder-utils writes the log under the module directory.
      const installLog = await readFile(
        path.join(home, ".coder-modules/coder-labs/nix/logs/install.log"),
        "utf8",
      );
      expect(installLog).toContain("nix develop environment is ready.");
    });
  }, 30_000);
});
