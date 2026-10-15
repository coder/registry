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
  type TerraformState,
} from "~test";

const run = async (cmd: string[], env: Record<string, string> = {}) => {
  const proc = Bun.spawn(cmd, {
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env, ...env },
  });
  const [code, stdout, stderr] = await Promise.all([
    proc.exited,
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  if (code !== 0)
    throw new Error(`${cmd[0]} exited ${code}\n${stdout}\n${stderr}`);
  return stdout;
};
const executable = async (file: string, body: string) => {
  await writeFile(file, body);
  await chmod(file, 0o755);
};
const withHome = async (fn: (home: string, bin: string) => Promise<void>) => {
  const home = await mkdtemp(path.join(tmpdir(), "nix-module-"));
  try {
    const bin = path.join(home, ".nix-profile/bin");
    await mkdir(bin, { recursive: true });
    await executable(
      path.join(bin, "nix"),
      '#!/usr/bin/env bash\nprintf "%s\\n" "$PWD" "$NIX_CONFIG" "--- ARGS" "$@" | tee "$HOME/nix.log"\n',
    );
    await executable(path.join(bin, "coder"), "#!/usr/bin/env bash\nexit 0\n");
    await fn(home, bin);
  } finally {
    await rm(home, { recursive: true, force: true });
  }
};
// Simulate the agent expanding coder_env values against the workspace environment.
const agentEnv = (state: TerraformState, home: string) => ({
  HOME: home,
  PATH: findResourceInstance(state, "coder_env", "path")
    .value.replaceAll("$PATH", "/usr/bin:/bin")
    .replaceAll("$HOME", home),
  NIX_CONFIG: findResourceInstance(state, "coder_env", "nix_config").value,
});

const developState = (develop: Record<string, unknown>) =>
  runTerraformApply(import.meta.dir, {
    agent_id: "foo",
    nixos: JSON.stringify({ enabled: false }),
    config: JSON.stringify({
      "extra-substituters": ["https://cache.example.org"],
    }),
    develop: JSON.stringify({ enabled: true, ...develop }),
  });

describe("nix", async () => {
  await runTerraformInit(import.meta.dir);

  it("app uses the exported PATH and NIX_CONFIG, raw path and selected shell", async () => {
    await withHome(async (home) => {
      const project = path.join(home, "my 'project");
      await mkdir(project);
      const state = await developState({
        path: '"$HOME/my \'project"',
        shell: "ci",
        prebuild: false,
      });
      const app = findResourceInstance(state, "coder_app", "develop");
      const script = path.join(home, "app.sh");
      await executable(script, app.command);
      expect(app.slug).toBe("nix-develop");
      const stdout = await run([script], agentEnv(state, home));
      expect(stdout.trimEnd().split("\n")).toEqual([
        project,
        "extra-substituters = https://cache.example.org",
        "extra-experimental-features = nix-command flakes",
        "--- ARGS",
        "develop",
        "--profile",
        path.join(home, ".coder-modules/coder-labs/nix/develop/profile"),
        ".#ci",
      ]);
    });
  });

  it("prebuild waits for the clone index before entering the dev shell", async () => {
    await withHome(async (home, bin) => {
      const state = await developState({ path: "~/project" });
      const script = findResourceInstance(
        state,
        "coder_script",
        "install_script",
      );
      const nix = path.join(bin, "nix");
      const originalNix = await readFile(nix, "utf8");
      await executable(
        nix,
        originalNix.replace(
          "#!/usr/bin/env bash\n",
          '#!/usr/bin/env bash\nif ! git ls-files --error-unmatch -- flake.nix >/dev/null 2>&1; then echo "flake.nix is not tracked" >&2; exit 1; fi\n',
        ),
      );
      const appear = (async () => {
        await Bun.sleep(1500);
        const project = path.join(home, "project");
        await mkdir(project);
        await run(["git", "-C", project, "init", "-q"]);
        await writeFile(path.join(project, "flake.nix"), "{}\n");
        // Like a clone checkout: the file appears before the index is written.
        await Bun.sleep(3000);
        await run(["git", "-C", project, "add", "flake.nix"]);
      })();
      const stdout = await run(
        ["bash", "-c", script.script],
        agentEnv(state, home),
      );
      await appear;
      expect(stdout).toContain("Waiting for");
      expect(stdout).toContain("nix develop environment is ready.");
      expect(
        (await readFile(path.join(home, "nix.log"), "utf8"))
          .trimEnd()
          .split("\n"),
      ).toEqual([
        path.join(home, "project"),
        "extra-substituters = https://cache.example.org",
        "extra-experimental-features = nix-command flakes",
        "--- ARGS",
        "develop",
        "--profile",
        path.join(home, ".coder-modules/coder-labs/nix/develop/profile"),
        ".",
        "--command",
        "true",
      ]);
      expect(
        await readFile(
          path.join(home, ".coder-modules/coder-labs/nix/logs/install.log"),
          "utf8",
        ),
      ).toContain("environment is ready");
      // A flake outside Git needs no index and must still prebuild.
      await rm(path.join(home, "project/.git"), { recursive: true });
      await executable(nix, originalNix);
      expect(
        await run(["bash", "-c", script.script], agentEnv(state, home)),
      ).toContain("nix develop environment is ready.");
    });
  }, 30_000);

  it("boot adopts the checkout, fast-forwards, skips unchanged builds and preserves local work", async () => {
    await withHome(async (home, bin) => {
      const remote = path.join(home, "remote");
      const checkout = path.join(home, "checkout");
      const env = {
        HOME: home,
        PATH: `${bin}:/usr/bin:/bin`,
        STATE_DIR: path.join(home, "state"),
        GIT_CONFIG_GLOBAL: "/dev/null",
        GIT_CONFIG_NOSYSTEM: "1",
        CODER_LOG_LIBRARY: path.join(home, "log.sh"),
      };
      await writeFile(
        env.CODER_LOG_LIBRARY,
        'coder_log() { shift; echo "$*"; }\ncoder_log_pipe() { cat; }\n',
      );
      const git = (...args: string[]) =>
        run(["git", "-C", remote, ...args], env);
      await mkdir(remote);
      await git("init", "-q", "-b", "main");
      await git("config", "user.name", "Test");
      await git("config", "user.email", "test@example.org");
      await writeFile(path.join(remote, "flake.nix"), "initial\n");
      await writeFile(path.join(remote, ".gitignore"), "secret\n");
      await git("add", ".");
      await git("commit", "-qm", "initial");
      await mkdir(checkout);
      await writeFile(
        path.join(checkout, "hardware-configuration.nix"),
        "keep\n",
      );
      await writeFile(path.join(checkout, "secret"), "keep-secret\n");
      await executable(
        path.join(bin, "nixos-rebuild"),
        '#!/usr/bin/env bash\nprintf "%s\\n" "$NIX_CONFIG" >> "$HOME/rebuild.log"\necho rebuilt\n',
      );
      const state = await runTerraformApply(import.meta.dir, {
        nixos: JSON.stringify({
          flake_ref: `file://${remote}?ref=main`,
          flake_attr: "host",
          flake_dir: checkout,
          log_dir: path.join(home, "logs"),
        }),
        config: JSON.stringify({ "max-jobs": "auto" }),
      });
      const script = path.join(home, "boot.sh");
      await executable(script, state.outputs.boot_script.value as string);
      const boot = () => run([script], env);
      expect(await boot()).toContain("Switch complete");
      expect(
        await readFile(
          path.join(checkout, "hardware-configuration.nix"),
          "utf8",
        ),
      ).toBe("keep\n");
      expect(await readFile(path.join(checkout, "secret"), "utf8")).toBe(
        "keep-secret\n",
      );
      expect(await readFile(path.join(home, "rebuild.log"), "utf8")).toBe(
        "max-jobs = auto\nextra-experimental-features = nix-command flakes\n",
      );
      expect(await boot()).toContain("skipping rebuild");
      await writeFile(path.join(remote, "flake.nix"), "updated\n");
      await git("commit", "-qam", "update");
      expect(await boot()).toContain("Switch complete");
      expect(await readFile(path.join(checkout, "flake.nix"), "utf8")).toBe(
        "updated\n",
      );
      await writeFile(path.join(checkout, "flake.nix"), "local edit\n");
      expect(await boot()).toContain("Switch complete");
      expect(await readFile(path.join(checkout, "flake.nix"), "utf8")).toBe(
        "local edit\n",
      );
      await run(
        [
          "git",
          "-C",
          checkout,
          "remote",
          "set-url",
          "origin",
          "file:///different-repo",
        ],
        env,
      );
      expect(await boot()).toContain("tracks another repository");
      expect(await readFile(path.join(checkout, "secret"), "utf8")).toBe(
        "keep-secret\n",
      );
    });
  });
});
