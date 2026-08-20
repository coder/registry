import { describe, expect, it } from "bun:test";
import {
  execContainer,
  readFileContainer,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  type TerraformState,
} from "~test";
import { writeExecutable } from "../agentapi/test-util";

// coder-utils orchestrates this module's scripts and produces multiple
// coder_script resources (install + start), so the single-script helpers from
// ~test do not apply. Collect every coder_script by display name instead.
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
  const install = byDisplayName["Shux: Install Script"];
  const start = byDisplayName["Shux: Start Script"];
  if (!install || !start) {
    throw new Error(
      `install/start scripts not found in terraform state (found: ${Object.keys(byDisplayName).join(", ")})`,
    );
  }
  return { install, start };
};

// Mock `coder` CLI so `coder exp sync` calls from coder-utils wrappers
// succeed without a real control plane.
const mockCoderCli = async (id: string) => {
  await writeExecutable({
    containerId: id,
    filePath: "/usr/bin/coder",
    content: "#!/bin/bash\nexit 0\n",
  });
};

const runScript = async (id: string, script: string) => {
  const output = await execContainer(id, ["bash", "-c", script]);
  if (output.exitCode !== 0) {
    console.log("STDOUT:\n" + output.stdout);
    console.log("STDERR:\n" + output.stderr);
  }
  return output;
};

describe("shux", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("installs and starts via tarball fallback", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install_prefix: "/tmp/shux",
      log_path: "/tmp/shux.log",
    });
    const scripts = collectScripts(state);

    const id = await runContainer("alpine/curl");
    try {
      const setup = await execContainer(id, [
        "sh",
        "-c",
        "apk add --no-cache bash tar gzip ca-certificates findutils nodejs > /dev/null && update-ca-certificates",
      ]);
      expect(setup.exitCode).toBe(0);
      await mockCoderCli(id);

      const install = await runScript(id, scripts.install);
      expect(install.exitCode).toBe(0);
      expect(install.stdout).toContain(
        "📥 No package manager found; downloading tarball from registry...",
      );
      expect(install.stdout).toContain(
        "🥳 shux has been installed in /tmp/shux",
      );

      const start = await runScript(id, scripts.start);
      expect(start.exitCode).toBe(0);
      expect(start.stdout).toContain("🚀 Starting shux server on port 4000...");
      expect(start.stdout).toContain("Check logs at /tmp/shux.log!");
    } finally {
      await removeContainer(id);
    }
  }, 120000);

  it("parses custom additional_arguments", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
      install_prefix: "/tmp/shux",
      log_path: "/tmp/shux.log",
      additional_arguments:
        "--open-mode pinned --add-project '/workspaces/my repo'",
    });
    const scripts = collectScripts(state);

    const id = await runContainer("alpine/curl");
    try {
      const setup = await execContainer(id, [
        "sh",
        "-c",
        `apk add --no-cache bash > /dev/null
mkdir -p /tmp/shux
cat <<'EOF' > /tmp/shux/shux
#!/usr/bin/env sh
i=1
for arg in "$@"; do
  echo "arg$i=$arg"
  i=$((i + 1))
done
EOF
chmod +x /tmp/shux/shux`,
      ]);
      expect(setup.exitCode).toBe(0);
      await mockCoderCli(id);

      // In production the install script always runs before start (coder exp
      // sync ordering) and creates the module data directories the start
      // wrapper expects. In offline mode it only verifies the binary exists.
      const install = await runScript(id, scripts.install);
      expect(install.exitCode).toBe(0);

      const start = await runScript(id, scripts.start);
      expect(start.exitCode).toBe(0);

      await execContainer(id, ["sh", "-c", "sleep 1"]);
      const log = await readFileContainer(id, "/tmp/shux.log");
      expect(log).toContain("arg1=server");
      expect(log).toContain("arg2=--port");
      expect(log).toContain("arg3=4000");
      expect(log).toContain("arg4=--open-mode");
      expect(log).toContain("arg5=pinned");
      expect(log).toContain("arg6=--add-project");
      expect(log).toContain("arg7=/workspaces/my repo");
    } finally {
      await removeContainer(id);
    }
  }, 120000);

  it("logs signal-based exits after startup", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
      install_prefix: "/tmp/shux",
      log_path: "/tmp/shux.log",
    });
    const scripts = collectScripts(state);

    const id = await runContainer("alpine/curl");
    try {
      const setup = await execContainer(id, [
        "sh",
        "-c",
        `apk add --no-cache bash > /dev/null
mkdir -p /tmp/shux
cat <<'EOF' > /tmp/shux/shux
#!/usr/bin/env sh
target_pid="$$"
(
  sleep 1
  kill -9 "$target_pid"
) &
while true; do
  sleep 1
done
EOF
chmod +x /tmp/shux/shux`,
      ]);
      expect(setup.exitCode).toBe(0);
      await mockCoderCli(id);

      // In production the install script always runs before start (coder exp
      // sync ordering) and creates the module data directories the start
      // wrapper expects. In offline mode it only verifies the binary exists.
      const install = await runScript(id, scripts.install);
      expect(install.exitCode).toBe(0);

      const start = await runScript(id, scripts.start);
      expect(start.exitCode).toBe(0);

      await execContainer(id, ["sh", "-c", "sleep 2"]);
      const log = await readFileContainer(id, "/tmp/shux.log");
      expect(log).toContain("shell exit code 137");
      expect(log).toContain(
        "SIGKILL usually means the process was killed externally or by the OOM killer.",
      );
    } finally {
      await removeContainer(id);
    }
  }, 120000);

  it("restarts after a clean exit when enabled", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
      install_prefix: "/tmp/shux",
      log_path: "/tmp/shux.log",
      restart_on_kill: true,
      restart_delay_seconds: 1,
      max_restart_attempts: 1,
    });
    const scripts = collectScripts(state);

    const id = await runContainer("alpine/curl");
    try {
      const setup = await execContainer(id, [
        "sh",
        "-c",
        `apk add --no-cache bash > /dev/null
mkdir -p /tmp/shux
cat <<'EOF' > /tmp/shux/shux
#!/usr/bin/env sh
run_count_file="/tmp/shux-run-count"
run_count=0
if [ -f "$run_count_file" ]; then
  run_count=$(cat "$run_count_file")
fi
run_count=$((run_count + 1))
printf '%s' "$run_count" > "$run_count_file"
echo "run=$run_count"
if [ "$run_count" -eq 1 ]; then
  mkdir -p "$HOME/.shux" "$HOME/.mux"
  touch "$HOME/.shux/server.lock" "$HOME/.mux/server.lock"
  exit 0
fi
if [ -f "$HOME/.shux/server.lock" ] || [ -f "$HOME/.mux/server.lock" ]; then
  echo "lock=present"
else
  echo "lock=cleaned"
fi
exit 0
EOF
chmod +x /tmp/shux/shux`,
      ]);
      expect(setup.exitCode).toBe(0);
      await mockCoderCli(id);

      // In production the install script always runs before start (coder exp
      // sync ordering) and creates the module data directories the start
      // wrapper expects. In offline mode it only verifies the binary exists.
      const install = await runScript(id, scripts.install);
      expect(install.exitCode).toBe(0);

      const start = await runScript(id, scripts.start);
      expect(start.exitCode).toBe(0);

      await execContainer(id, ["sh", "-c", "sleep 4"]);
      const log = await readFileContainer(id, "/tmp/shux.log");
      const runCount = await readFileContainer(id, "/tmp/shux-run-count");
      expect(log).toContain("run=1");
      expect(log).toContain("shux server exited cleanly.");
      expect(log).toContain(
        "Waiting 1 seconds before restarting shux after it exited.",
      );
      expect(log).toContain(
        "Removing /root/.shux/server.lock and /root/.mux/server.lock before restarting shux.",
      );
      expect(log).toContain("run=2");
      expect(log).toContain("lock=cleaned");
      expect(log).toContain(
        "Reached the max restart attempts limit (1); not restarting shux again.",
      );
      expect(runCount.trim()).toBe("2");
    } finally {
      await removeContainer(id);
    }
  }, 120000);

  it("restarts after SIGTERM when enabled", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
      install_prefix: "/tmp/shux",
      log_path: "/tmp/shux.log",
      restart_on_kill: true,
      restart_delay_seconds: 1,
      max_restart_attempts: 1,
    });
    const scripts = collectScripts(state);

    const id = await runContainer("alpine/curl");
    try {
      const setup = await execContainer(id, [
        "sh",
        "-c",
        `apk add --no-cache bash > /dev/null
mkdir -p /tmp/shux
cat <<'EOF' > /tmp/shux/shux
#!/usr/bin/env sh
run_count_file="/tmp/shux-run-count"
run_count=0
if [ -f "$run_count_file" ]; then
  run_count=$(cat "$run_count_file")
fi
run_count=$((run_count + 1))
printf '%s' "$run_count" > "$run_count_file"
echo "run=$run_count"
if [ "$run_count" -eq 1 ]; then
  kill -TERM $$
fi
exit 0
EOF
chmod +x /tmp/shux/shux`,
      ]);
      expect(setup.exitCode).toBe(0);
      await mockCoderCli(id);

      // In production the install script always runs before start (coder exp
      // sync ordering) and creates the module data directories the start
      // wrapper expects. In offline mode it only verifies the binary exists.
      const install = await runScript(id, scripts.install);
      expect(install.exitCode).toBe(0);

      const start = await runScript(id, scripts.start);
      expect(start.exitCode).toBe(0);

      await execContainer(id, ["sh", "-c", "sleep 4"]);
      const log = await readFileContainer(id, "/tmp/shux.log");
      const runCount = await readFileContainer(id, "/tmp/shux-run-count");
      expect(log).toContain("run=1");
      expect(log).toContain("signal TERM (15); shell exit code 143.");
      expect(log).toContain(
        "Waiting 1 seconds before restarting shux after it exited.",
      );
      expect(log).toContain("run=2");
      expect(log).toContain(
        "Reached the max restart attempts limit (1); not restarting shux again.",
      );
      expect(runCount.trim()).toBe("2");
    } finally {
      await removeContainer(id);
    }
  }, 120000);

  it("installs and starts with npm present", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install_prefix: "/tmp/shux",
      log_path: "/tmp/shux.log",
    });
    const scripts = collectScripts(state);

    const id = await runContainer("node:20-alpine");
    try {
      const setup = await execContainer(id, ["sh", "-c", "apk add bash"]);
      expect(setup.exitCode).toBe(0);
      await mockCoderCli(id);

      const install = await runScript(id, scripts.install);
      expect(install.exitCode).toBe(0);
      expect(install.stdout).toContain(
        "📦 Installing shux via npm into /tmp/shux...",
      );
      expect(install.stdout).toContain(
        "⏭️  Skipping lifecycle scripts with --ignore-scripts",
      );
      expect(install.stdout).toContain(
        "🥳 shux has been installed in /tmp/shux",
      );

      const start = await runScript(id, scripts.start);
      expect(start.exitCode).toBe(0);
      expect(start.stdout).toContain("🚀 Starting shux server on port 4000...");
      expect(start.stdout).toContain("Check logs at /tmp/shux.log!");
    } finally {
      await removeContainer(id);
    }
  }, 300000);
});
