import { describe, expect, it } from "bun:test";
import {
  execContainer,
  findResourceInstance,
  readFileContainer,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  type scriptOutput,
  type TerraformState,
  testRequiredVariables,
} from "~test";

// Default install_prefix and log_path with HOME=/root inside the test containers.
const MODULE_ROOT = "/root/.coder-modules/coder/mux";
const LOG_PATH = `${MODULE_ROOT}/logs/mux.log`;

// Like executeScriptInContainer, but removes the container inside the test:
// deleting a container that holds a full @coder/xum install takes longer than
// the few seconds the global afterAll cleanup hook allows.
const executeInstallScriptInContainer = async (
  state: TerraformState,
  image: string,
  before: string,
): Promise<scriptOutput> => {
  const instance = findResourceInstance(state, "coder_script");
  const id = await runContainer(image);
  try {
    await execContainer(id, ["sh", "-c", before]);
    const resp = await execContainer(id, ["sh", "-c", instance.script]);
    return {
      exitCode: resp.exitCode,
      stdout: resp.stdout.trim().split("\n"),
      stderr: resp.stderr.trim().split("\n"),
    };
  } finally {
    await removeContainer(id);
  }
};

describe("mux", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("runs with default", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });

    const output = await executeInstallScriptInContainer(
      state,
      "alpine/curl",
      "apk add --no-cache bash tar gzip ca-certificates findutils nodejs && update-ca-certificates",
    );
    if (output.exitCode !== 0) {
      console.log("STDOUT:\n" + output.stdout.join("\n"));
      console.log("STDERR:\n" + output.stderr.join("\n"));
    }
    expect(output.exitCode).toBe(0);
    const expectedLines = [
      "📥 No package manager found; downloading tarball from registry...",
      `🥳 mux has been installed in ${MODULE_ROOT}`,
      "🚀 Starting mux server on port 4000...",
      `Check logs at ${LOG_PATH}!`,
    ];
    for (const line of expectedLines) {
      expect(output.stdout).toContain(line);
    }
  }, 60000);

  it("parses custom additional_arguments", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
      additional_arguments:
        "--open-mode pinned --add-project '/workspaces/my repo'",
    });

    const instance = findResourceInstance(state, "coder_script");
    const id = await runContainer("alpine/curl");

    try {
      const setup = await execContainer(id, [
        "sh",
        "-c",
        `apk add --no-cache bash >/dev/null
mkdir -p ${MODULE_ROOT}
cat <<'EOF' > ${MODULE_ROOT}/mux
#!/usr/bin/env sh
i=1
for arg in "$@"; do
  echo "arg$i=$arg"
  i=$((i + 1))
done
EOF
chmod +x ${MODULE_ROOT}/mux`,
      ]);
      expect(setup.exitCode).toBe(0);

      const output = await execContainer(id, ["sh", "-c", instance.script]);
      if (output.exitCode !== 0) {
        console.log("STDOUT:\n" + output.stdout);
        console.log("STDERR:\n" + output.stderr);
      }
      expect(output.exitCode).toBe(0);

      await execContainer(id, ["sh", "-c", "sleep 1"]);
      const log = await readFileContainer(id, LOG_PATH);
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

  it("logs signal-based exits after startup", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
    });

    const instance = findResourceInstance(state, "coder_script");
    const id = await runContainer("alpine/curl");

    try {
      const setup = await execContainer(id, [
        "sh",
        "-c",
        `apk add --no-cache bash >/dev/null
mkdir -p ${MODULE_ROOT}
cat <<'EOF' > ${MODULE_ROOT}/mux
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
chmod +x ${MODULE_ROOT}/mux`,
      ]);
      expect(setup.exitCode).toBe(0);

      const output = await execContainer(id, ["sh", "-c", instance.script]);
      if (output.exitCode !== 0) {
        console.log("STDOUT:\n" + output.stdout);
        console.log("STDERR:\n" + output.stderr);
      }
      expect(output.exitCode).toBe(0);

      await execContainer(id, ["sh", "-c", "sleep 2"]);
      const log = await readFileContainer(id, LOG_PATH);
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

    const instance = findResourceInstance(state, "coder_script");
    const id = await runContainer("alpine/curl");

    try {
      const setup = await execContainer(id, [
        "sh",
        "-c",
        `apk add --no-cache bash >/dev/null
mkdir -p ${MODULE_ROOT}
cat <<'EOF' > ${MODULE_ROOT}/mux
#!/usr/bin/env sh
run_count_file="${MODULE_ROOT}/run-count"
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
exit 0
EOF
chmod +x ${MODULE_ROOT}/mux`,
      ]);
      expect(setup.exitCode).toBe(0);

      const output = await execContainer(id, ["sh", "-c", instance.script]);
      if (output.exitCode !== 0) {
        console.log("STDOUT:\n" + output.stdout);
        console.log("STDERR:\n" + output.stderr);
      }
      expect(output.exitCode).toBe(0);

      await execContainer(id, ["sh", "-c", "sleep 4"]);
      const log = await readFileContainer(id, LOG_PATH);
      const runCount = await readFileContainer(id, `${MODULE_ROOT}/run-count`);
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

    const instance = findResourceInstance(state, "coder_script");
    const id = await runContainer("alpine/curl");

    try {
      const setup = await execContainer(id, [
        "sh",
        "-c",
        `apk add --no-cache bash >/dev/null
mkdir -p ${MODULE_ROOT}
cat <<'EOF' > ${MODULE_ROOT}/mux
#!/usr/bin/env sh
run_count_file="${MODULE_ROOT}/run-count"
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
chmod +x ${MODULE_ROOT}/mux`,
      ]);
      expect(setup.exitCode).toBe(0);

      const output = await execContainer(id, ["sh", "-c", instance.script]);
      if (output.exitCode !== 0) {
        console.log("STDOUT:\n" + output.stdout);
        console.log("STDERR:\n" + output.stderr);
      }
      expect(output.exitCode).toBe(0);

      await execContainer(id, ["sh", "-c", "sleep 4"]);
      const log = await readFileContainer(id, LOG_PATH);
      const runCount = await readFileContainer(id, `${MODULE_ROOT}/run-count`);
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

  it("runs with npm present", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });

    const output = await executeInstallScriptInContainer(
      state,
      "node:20-alpine",
      "apk add bash",
    );

    expect(output.exitCode).toBe(0);
    const expectedLines = [
      `📦 Installing @coder/xum via npm into ${MODULE_ROOT}...`,
      "⏭️  Skipping lifecycle scripts with --ignore-scripts",
      `🥳 mux has been installed in ${MODULE_ROOT}`,
      "🚀 Starting mux server on port 4000...",
      `Check logs at ${LOG_PATH}!`,
    ];
    for (const line of expectedLines) {
      expect(output.stdout).toContain(line);
    }
  }, 180000);
});
