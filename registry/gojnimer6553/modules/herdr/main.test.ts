import { describe, expect, it, setDefaultTimeout } from "bun:test";
import {
  execContainer,
  readFileContainer,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  writeCoder,
  writeFileContainer,
  type TerraformState,
} from "~test";

// coder-utils orchestrates this module's scripts and produces multiple
// coder_script resources (install, start). Collect them by their
// coder-utils-generated display_name so each can be executed in run order.
interface ModuleScripts {
  install: string;
  start: string;
}

const collectScripts = (state: TerraformState): ModuleScripts => {
  const byDisplayName: Record<string, string> = {};
  for (const resource of state.resources) {
    if (resource.type !== "coder_script") continue;
    for (const instance of resource.instances) {
      const attrs = instance.attributes as Record<string, unknown>;
      const displayName = attrs.display_name as string | undefined;
      const script = attrs.script as string | undefined;
      if (displayName && script) {
        byDisplayName[displayName] = script;
      }
    }
  }
  const install = byDisplayName["Herdr: Install Script"];
  const start = byDisplayName["Herdr: Start Script"];
  if (!install) {
    throw new Error("install script not found in terraform state");
  }
  if (!start) {
    throw new Error("start script not found in terraform state");
  }
  return { install, start };
};

const HERDR_BIN_PATH = "/root/.local/bin/herdr";
const PLUGIN_LOG_PATH = "/root/.herdr-plugin-log";

// Fake herdr binary: enough of the real CLI's surface for this module's
// scripts to drive (--version, status, plugin install <spec> --yes) without
// a real network install or a real Herdr server. Any spec containing
// "explode" simulates a plugin that fails to install, to exercise the
// continue-on-failure path. The default (no matched subcommand) branch
// stands in for `herdr` launching its server/session -- it just sleeps, like
// the real long-running process would, and records the HERDR_SESSION env var
// it was started with so tests can confirm session_name was forwarded.
const FAKE_HERDR_BINARY = [
  "#!/bin/bash",
  `LOG_FILE="${PLUGIN_LOG_PATH}"`,
  'if [ "$1" = "--version" ]; then',
  '  echo "herdr fake-version 0.0.0-test"',
  "  exit 0",
  'elif [ "$1" = "status" ]; then',
  "  exit 0",
  'elif [ "$1" = "plugin" ] && [ "$2" = "install" ]; then',
  '  spec="$3"',
  '  case "$spec" in',
  "    *explode*)",
  '      echo "simulated failure for $spec" >&2',
  "      exit 1",
  "      ;;",
  "    *)",
  '      echo "$spec" >> "$LOG_FILE"',
  "      exit 0",
  "      ;;",
  "  esac",
  "else",
  '  echo "herdr-server-started session=${HERDR_SESSION:-default}"',
  "  sleep 3600",
  "fi",
].join("\n");

const installFakeHerdrBinary = async (id: string) => {
  await execContainer(id, ["mkdir", "-p", "/root/.local/bin"]);
  await writeFileContainer(id, HERDR_BIN_PATH, FAKE_HERDR_BINARY);
  await execContainer(id, ["chmod", "755", HERDR_BIN_PATH]);
};

setDefaultTimeout(120 * 1000);

describe("herdr", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("skips installation when install=false", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
    });
    const { install, start } = collectScripts(state);

    const id = await runContainer("alpine/curl");
    try {
      await writeCoder(id, "#!/bin/sh\nexit 0\n");
      await execContainer(id, ["sh", "-c", "apk add --no-cache bash tmux"]);

      const output = await execContainer(id, ["bash", "-c", install]);
      expect(output.exitCode).toBe(0);
      expect(output.stdout).toContain(
        "⏭️  install=false; skipping Herdr installation.",
      );

      // The start script should fail fast: no herdr binary was ever installed.
      const startOutput = await execContainer(id, ["bash", "-c", start]);
      expect(startOutput.exitCode).not.toBe(0);
      expect(startOutput.stderr + startOutput.stdout).toContain(
        "herdr binary not found",
      );
    } finally {
      await removeContainer(id);
    }
  });

  it("auto-installs tmux via the system package manager when missing", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
    });
    const { install } = collectScripts(state);

    const id = await runContainer("alpine/curl");
    try {
      await writeCoder(id, "#!/bin/sh\nexit 0\n");
      // Deliberately no tmux here -- running as root (this image's default
      // user), so no sudo is needed for the install script's apk fallback.
      await execContainer(id, ["sh", "-c", "apk add --no-cache bash"]);

      const output = await execContainer(id, ["bash", "-c", install]);
      expect(output.exitCode).toBe(0);
      expect(output.stdout).toContain("tmux not found on PATH; attempting");
      expect(output.stdout).toContain("tmux installed automatically");

      const tmuxCheck = await execContainer(id, [
        "bash",
        "-c",
        "command -v tmux",
      ]);
      expect(tmuxCheck.exitCode).toBe(0);
    } finally {
      await removeContainer(id);
    }
  });

  it("fails install with a clear error when tmux is missing and neither root nor sudo is available", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
    });
    const { install } = collectScripts(state);

    const id = await runContainer("node:22-bookworm-slim");
    try {
      await writeCoder(id, "#!/bin/bash\nexit 0\n");
      await execContainer(id, ["useradd", "-m", "testuser"]);
      const output = await execContainer(
        id,
        ["bash", "-c", install],
        ["-u", "testuser"],
      );
      expect(output.exitCode).not.toBe(0);
      expect(output.stdout).toContain("neither root nor passwordless sudo");
    } finally {
      await removeContainer(id);
    }
  });

  it("starts Herdr in a detached tmux session and installs configured plugins", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
      tmux_session: "herdr-test-1",
      session_name: "isolated",
      plugins: JSON.stringify(["fake/plugin-one", "fake/plugin-two"]),
    });
    const { install, start } = collectScripts(state);

    const id = await runContainer("node:22-bookworm-slim");
    try {
      await writeCoder(id, "#!/bin/bash\nexit 0\n");
      // install=false, but the install script still creates the module's
      // scripts/logs directory tree (and, incidentally, ensures tmux) --
      // running it first mirrors how coder-utils always runs install before
      // start on a real workspace.
      await execContainer(id, ["bash", "-c", install]);
      await installFakeHerdrBinary(id);

      const output = await execContainer(id, ["bash", "-c", start]);
      expect(output.exitCode).toBe(0);
      expect(output.stdout).toContain(
        "🚀 Starting Herdr in the background (tmux session 'herdr-test-1')",
      );
      expect(output.stdout).toContain("✅ Installed plugin 'fake/plugin-one'.");
      expect(output.stdout).toContain("✅ Installed plugin 'fake/plugin-two'.");

      const sessions = await execContainer(id, [
        "bash",
        "-c",
        "tmux list-sessions",
      ]);
      expect(sessions.stdout).toContain("herdr-test-1");

      const pluginLog = await readFileContainer(id, PLUGIN_LOG_PATH);
      expect(pluginLog).toContain("fake/plugin-one");
      expect(pluginLog).toContain("fake/plugin-two");

      // session_name should be forwarded as HERDR_SESSION to the launched
      // process. Read via capture-pane (current on-screen content), not the
      // piped log file: "tmux pipe-pane" only starts forwarding output after
      // it attaches, which happens in a separate command right after
      // "new-session" -- output the wrapped process printed in that gap
      // never reaches the log. capture-pane has no such race.
      const pane = await execContainer(id, [
        "bash",
        "-c",
        "tmux capture-pane -t herdr-test-1 -p",
      ]);
      expect(pane.stdout).toContain("session=isolated");
    } finally {
      await removeContainer(id);
    }
  });

  it("leaves an already-running Herdr session alone on a second start", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
      tmux_session: "herdr-test-2",
    });
    const { install, start } = collectScripts(state);

    const id = await runContainer("node:22-bookworm-slim");
    try {
      await writeCoder(id, "#!/bin/bash\nexit 0\n");
      await execContainer(id, ["bash", "-c", install]);
      await installFakeHerdrBinary(id);

      const first = await execContainer(id, ["bash", "-c", start]);
      expect(first.exitCode).toBe(0);
      expect(first.stdout).toContain("🚀 Starting Herdr");

      const second = await execContainer(id, ["bash", "-c", start]);
      expect(second.exitCode).toBe(0);
      expect(second.stdout).toContain(
        "tmux session 'herdr-test-2' is already running",
      );

      const sessions = await execContainer(id, [
        "bash",
        "-c",
        "tmux list-sessions | grep -c herdr-test-2",
      ]);
      expect(sessions.stdout.trim()).toBe("1");
    } finally {
      await removeContainer(id);
    }
  });

  it("continues installing remaining plugins when one fails", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
      tmux_session: "herdr-test-3",
      plugins: JSON.stringify(["fake/explode-plugin", "fake/plugin-ok"]),
    });
    const { install, start } = collectScripts(state);

    const id = await runContainer("node:22-bookworm-slim");
    try {
      await writeCoder(id, "#!/bin/bash\nexit 0\n");
      await execContainer(id, ["bash", "-c", install]);
      await installFakeHerdrBinary(id);

      const output = await execContainer(id, ["bash", "-c", start]);
      // A single plugin failure must not fail the whole start script.
      expect(output.exitCode).toBe(0);
      expect(output.stdout).toContain(
        "❌ Failed to install plugin 'fake/explode-plugin'",
      );
      expect(output.stdout).toContain("✅ Installed plugin 'fake/plugin-ok'.");
      expect(output.stdout).toContain(
        "One or more Herdr plugins failed to install",
      );

      const pluginLog = await readFileContainer(id, PLUGIN_LOG_PATH);
      expect(pluginLog).not.toContain("explode");
      expect(pluginLog).toContain("fake/plugin-ok");
    } finally {
      await removeContainer(id);
    }
  });

  it("runs post_start_script after Herdr and its plugins are up", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
      tmux_session: "herdr-test-4",
      plugins: JSON.stringify(["fake/plugin-one"]),
      post_start_script:
        '#!/bin/bash\necho "post-start ran, herdr version: $(herdr --version)"',
    });
    const { install, start } = collectScripts(state);

    const id = await runContainer("node:22-bookworm-slim");
    try {
      await writeCoder(id, "#!/bin/bash\nexit 0\n");
      await execContainer(id, ["bash", "-c", install]);
      await installFakeHerdrBinary(id);

      const output = await execContainer(id, ["bash", "-c", start]);
      expect(output.exitCode).toBe(0);

      const pluginIdx = output.stdout.indexOf(
        "✅ Installed plugin 'fake/plugin-one'.",
      );
      const postStartIdx = output.stdout.indexOf(
        "post-start ran, herdr version: herdr fake-version 0.0.0-test",
      );
      expect(pluginIdx).toBeGreaterThan(-1);
      expect(postStartIdx).toBeGreaterThan(pluginIdx);
    } finally {
      await removeContainer(id);
    }
  });

  it("fails the start script when post_start_script exits non-zero", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
      tmux_session: "herdr-test-5",
      post_start_script: "#!/bin/bash\necho boom >&2\nexit 1",
    });
    const { install, start } = collectScripts(state);

    const id = await runContainer("node:22-bookworm-slim");
    try {
      await writeCoder(id, "#!/bin/bash\nexit 0\n");
      await execContainer(id, ["bash", "-c", install]);
      await installFakeHerdrBinary(id);

      const output = await execContainer(id, ["bash", "-c", start]);
      expect(output.exitCode).not.toBe(0);
      expect(output.stdout + output.stderr).toContain("boom");
    } finally {
      await removeContainer(id);
    }
  });
});
