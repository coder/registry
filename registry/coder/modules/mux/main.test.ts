import { describe, expect, it } from "bun:test";
import {
  execContainer,
  readFileContainer,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  type TerraformState,
  testRequiredVariables,
} from "~test";

const MODULE_ROOT = "/root/.coder-modules/coder/mux";
const DEFAULT_MUX_BINARY = `${MODULE_ROOT}/mux`;
const DEFAULT_LOG_PATH = `${MODULE_ROOT}/logs/mux.log`;

// coder-utils renders one coder_script per lifecycle stage; pick them by display name.
const collectScripts = (state: TerraformState) => {
  const byDisplayName: Record<string, string> = {};
  for (const resource of state.resources) {
    if (resource.type !== "coder_script") continue;
    for (const instance of resource.instances) {
      const attrs = instance.attributes as Record<string, unknown>;
      byDisplayName[attrs.display_name as string] = attrs.script as string;
    }
  }
  const install = byDisplayName["Mux: Install Script"];
  const start = byDisplayName["Mux: Start Script"];
  if (!install || !start) {
    throw new Error(
      `missing mux scripts, found: ${Object.keys(byDisplayName).join(", ")}`,
    );
  }
  return { install, start };
};

// The coder-utils wrappers call `coder exp sync`; stub the CLI outside a real workspace.
const setupContainer = async (id: string, packages: string) => {
  const setup = await execContainer(id, [
    "sh",
    "-c",
    `${packages}
printf '#!/bin/sh\nexit 0\n' > /usr/local/bin/coder
chmod +x /usr/local/bin/coder`,
  ]);
  expect(setup.exitCode).toBe(0);
};

const writeFakeMux = async (id: string, path: string, body: string) => {
  const result = await execContainer(id, [
    "sh",
    "-c",
    `mkdir -p "$(dirname '${path}')"
cat <<'EOF' > '${path}'
${body}
EOF
chmod +x '${path}'`,
  ]);
  expect(result.exitCode).toBe(0);
};

const runScript = async (id: string, script: string) => {
  const output = await execContainer(id, ["bash", "-c", script]);
  if (output.exitCode !== 0) {
    console.log("STDOUT:\n" + output.stdout);
    console.log("STDERR:\n" + output.stderr);
  }
  return output;
};

const ECHO_ARGS_MUX = `#!/usr/bin/env sh
i=1
for arg in "$@"; do
  echo "arg$i=$arg"
  i=$((i + 1))
done`;

describe("mux", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("runs with default and reuses the tarball install on the next start", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });

    const scripts = collectScripts(state);
    const id = await runContainer("alpine/curl");

    try {
      await setupContainer(
        id,
        "apk add --no-cache bash tar gzip ca-certificates findutils nodejs >/dev/null && update-ca-certificates",
      );

      const install = await runScript(id, scripts.install);
      expect(install.exitCode).toBe(0);
      expect(install.stdout).toContain(
        "📥 No package manager found; downloading tarball from registry...",
      );
      expect(install.stdout).toContain(
        `🥳 mux has been installed in ${MODULE_ROOT}`,
      );

      const start = await runScript(id, scripts.start);
      expect(start.exitCode).toBe(0);
      expect(start.stdout).toContain("🚀 Starting mux server on port 4000...");
      expect(start.stdout).toContain(`Check logs at ${DEFAULT_LOG_PATH}!`);

      const second = await runScript(id, scripts.install);
      expect(second.exitCode).toBe(0);
      expect(second.stdout).toMatch(
        new RegExp(
          `🥳 mux@\\S+ is already installed in ${MODULE_ROOT}; skipping install`,
        ),
      );
      expect(second.stdout).not.toContain("📥 No package manager found");
    } finally {
      await removeContainer(id);
    }
  }, 120000);

  it("parses custom additional_arguments", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
      additional_arguments:
        "--open-mode pinned --add-project '/workspaces/my repo'",
    });

    const scripts = collectScripts(state);
    const id = await runContainer("alpine/curl");

    try {
      await setupContainer(id, "apk add --no-cache bash >/dev/null");
      await writeFakeMux(id, DEFAULT_MUX_BINARY, ECHO_ARGS_MUX);

      const install = await runScript(id, scripts.install);
      expect(install.exitCode).toBe(0);
      expect(install.stdout).toContain("🥳 Found a copy of mux");
      const start = await runScript(id, scripts.start);
      expect(start.exitCode).toBe(0);

      await execContainer(id, ["sh", "-c", "sleep 1"]);
      const log = await readFileContainer(id, DEFAULT_LOG_PATH);
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
  }, 60000);

  it("runs a copy pre-installed at the pre-1.6.0 path when install is false", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
    });

    const scripts = collectScripts(state);
    const id = await runContainer("alpine/curl");

    try {
      await setupContainer(id, "apk add --no-cache bash >/dev/null");
      await writeFakeMux(id, "/tmp/mux/mux", ECHO_ARGS_MUX);

      const install = await runScript(id, scripts.install);
      expect(install.exitCode).toBe(0);
      expect(install.stdout).toContain(
        "ℹ️ Using mux pre-installed at /tmp/mux",
      );
      expect(install.stdout).toContain("🥳 Found a copy of mux");
      const start = await runScript(id, scripts.start);
      expect(start.exitCode).toBe(0);

      await execContainer(id, ["sh", "-c", "sleep 1"]);
      const log = await readFileContainer(id, DEFAULT_LOG_PATH);
      expect(log).toContain("arg1=server");
    } finally {
      await removeContainer(id);
    }
  }, 60000);

  it("logs signal-based exits after startup", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
    });

    const scripts = collectScripts(state);
    const id = await runContainer("alpine/curl");

    try {
      await setupContainer(id, "apk add --no-cache bash >/dev/null");
      await writeFakeMux(
        id,
        DEFAULT_MUX_BINARY,
        `#!/usr/bin/env sh
target_pid="$$"
(
  sleep 1
  kill -9 "$target_pid"
) &
while true; do
  sleep 1
done`,
      );

      expect((await runScript(id, scripts.install)).exitCode).toBe(0);
      expect((await runScript(id, scripts.start)).exitCode).toBe(0);

      await execContainer(id, ["sh", "-c", "sleep 2"]);
      const log = await readFileContainer(id, DEFAULT_LOG_PATH);
      expect(log).toContain("shell exit code 137");
      expect(log).toContain(
        "SIGKILL usually means the process was killed externally or by the OOM killer.",
      );
    } finally {
      await removeContainer(id);
    }
  }, 60000);

  it("restarts after a clean exit when enabled", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
      restart_on_kill: true,
      restart_delay_seconds: 1,
      max_restart_attempts: 1,
    });

    const scripts = collectScripts(state);
    const id = await runContainer("alpine/curl");

    try {
      await setupContainer(id, "apk add --no-cache bash >/dev/null");
      await writeFakeMux(
        id,
        DEFAULT_MUX_BINARY,
        `#!/usr/bin/env sh
run_count_file="/tmp/mux-run-count"
run_count=0
if [ -f "$run_count_file" ]; then
  run_count=$(cat "$run_count_file")
fi
run_count=$((run_count + 1))
printf '%s' "$run_count" > "$run_count_file"
echo "run=$run_count"
if [ "$run_count" -eq 1 ]; then
  mkdir -p "$HOME/.mux"
  touch "$HOME/.mux/server.lock"
  exit 0
fi
if [ -f "$HOME/.mux/server.lock" ]; then
  echo "lock=present"
else
  echo "lock=cleaned"
fi
exit 0`,
      );

      expect((await runScript(id, scripts.install)).exitCode).toBe(0);
      expect((await runScript(id, scripts.start)).exitCode).toBe(0);

      await execContainer(id, ["sh", "-c", "sleep 4"]);
      const log = await readFileContainer(id, DEFAULT_LOG_PATH);
      const runCount = await readFileContainer(id, "/tmp/mux-run-count");
      expect(log).toContain("run=1");
      expect(log).toContain("mux server exited cleanly.");
      expect(log).toContain(
        "Waiting 1 seconds before restarting mux after it exited.",
      );
      expect(log).toContain(
        "Removing /root/.mux/server.lock before restarting mux.",
      );
      expect(log).toContain("run=2");
      expect(log).toContain("lock=cleaned");
      expect(log).toContain(
        "Reached the max restart attempts limit (1); not restarting mux again.",
      );
      expect(runCount.trim()).toBe("2");
    } finally {
      await removeContainer(id);
    }
  }, 60000);

  it("restarts after SIGTERM when enabled", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
      restart_on_kill: true,
      restart_delay_seconds: 1,
      max_restart_attempts: 1,
    });

    const scripts = collectScripts(state);
    const id = await runContainer("alpine/curl");

    try {
      await setupContainer(id, "apk add --no-cache bash >/dev/null");
      await writeFakeMux(
        id,
        DEFAULT_MUX_BINARY,
        `#!/usr/bin/env sh
run_count_file="/tmp/mux-run-count"
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
exit 0`,
      );

      expect((await runScript(id, scripts.install)).exitCode).toBe(0);
      expect((await runScript(id, scripts.start)).exitCode).toBe(0);

      await execContainer(id, ["sh", "-c", "sleep 4"]);
      const log = await readFileContainer(id, DEFAULT_LOG_PATH);
      const runCount = await readFileContainer(id, "/tmp/mux-run-count");
      expect(log).toContain("run=1");
      expect(log).toContain("signal TERM (15); shell exit code 143.");
      expect(log).toContain(
        "Waiting 1 seconds before restarting mux after it exited.",
      );
      expect(log).toContain("run=2");
      expect(log).toContain(
        "Reached the max restart attempts limit (1); not restarting mux again.",
      );
      expect(runCount.trim()).toBe("2");
    } finally {
      await removeContainer(id);
    }
  }, 60000);

  it("runs with npm present and reuses the install on the next start", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });

    const scripts = collectScripts(state);
    const id = await runContainer("node:20-alpine");

    try {
      await setupContainer(id, "apk add bash >/dev/null");

      const install = await runScript(id, scripts.install);
      expect(install.exitCode).toBe(0);
      const expectedLines = [
        `📦 Installing mux via npm into ${MODULE_ROOT}...`,
        "⏭️  Skipping lifecycle scripts with --ignore-scripts",
        `🥳 mux has been installed in ${MODULE_ROOT}`,
      ];
      for (const line of expectedLines) {
        expect(install.stdout).toContain(line);
      }
      const installLog = await readFileContainer(
        id,
        `${MODULE_ROOT}/logs/install.log`,
      );
      expect(installLog).toContain(
        `🥳 mux has been installed in ${MODULE_ROOT}`,
      );

      const start = await runScript(id, scripts.start);
      expect(start.exitCode).toBe(0);
      expect(start.stdout).toContain("🚀 Starting mux server on port 4000...");
      expect(start.stdout).toContain(`Check logs at ${DEFAULT_LOG_PATH}!`);

      const second = await runScript(id, scripts.install);
      expect(second.exitCode).toBe(0);
      expect(second.stdout).toMatch(
        new RegExp(
          `🥳 mux@\\S+ is already installed in ${MODULE_ROOT}; skipping install`,
        ),
      );
      expect(second.stdout).not.toContain("📦 Installing mux via npm");
    } finally {
      await removeContainer(id);
    }
  }, 240000);
});
