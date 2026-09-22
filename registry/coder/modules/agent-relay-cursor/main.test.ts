import {
  afterEach,
  beforeAll,
  describe,
  expect,
  it,
  setDefaultTimeout,
} from "bun:test";
import {
  execContainer,
  readFileContainer,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  type TerraformState,
  writeFileContainer,
} from "~test";

// The install and start scripts coder-utils wraps are exercised inside a
// throwaway container with a stub `agent` binary standing in for the
// Cursor CLI, so the supervisor lifecycle the relay's reaper depends on
// (idle, working, done, failed) is observed rather than grepped for. The
// real installer and the real worker are out of scope: both need the
// network and Cursor's side. `coder` is stubbed so the `coder exp sync`
// ordering calls succeed without a control plane.

let cleanupFunctions: (() => Promise<void>)[] = [];
const registerCleanup = (cleanup: () => Promise<void>) => {
  cleanupFunctions.push(cleanup);
};
afterEach(async () => {
  const cleanupFnsCopy = cleanupFunctions.slice().reverse();
  cleanupFunctions = [];
  for (const cleanup of cleanupFnsCopy) {
    try {
      await cleanup();
    } catch (error) {
      console.error("Error during cleanup:", error);
    }
  }
});

// coder-utils pins the layout; the container runs as root.
const MODULE_DIR = "/root/.coder-modules/coder/agent-relay-cursor";
const STATE_FILE = `${MODULE_DIR}/worker-state`;
// The pool name carries shell metacharacters to prove the value reaches
// the worker as a single argument rather than being parsed as code.
const POOL_NAME = 'safe"; touch /tmp/injected; #';
const DISPATCH_ENV = [
  "AGENT_RELAY_CURSOR_TOKEN=test-user-token",
  "CURSOR_AGENT_WORKER_ID=worker-123",
  `AGENT_RELAY_CURSOR_POOL_NAME=${POOL_NAME}`,
  "AGENT_RELAY_CURSOR_IDLE_RELEASE_TIMEOUT=600",
];

const setup = async (vars: Record<string, string> = {}) => {
  const state = await runTerraformApply(import.meta.dir, {
    agent_id: "foo",
    ...vars,
  });
  const scripts = collectScripts(state);
  const statusScript = state.outputs.status_metadata_script.value as string;
  const id = await runContainer("lorello/alpine-bash");
  registerCleanup(async () => {
    await removeContainer(id);
  });
  await stubBinary(id, "/usr/local/bin/coder", "exit 0");
  return { id, scripts, statusScript };
};

type Scripts = { install: string; start: string };

// coder-utils owns the coder_script resources; find ours by display name.
const collectScripts = (state: TerraformState): Scripts => {
  const byDisplayName: Record<string, string> = {};
  for (const resource of state.resources) {
    if (resource.type !== "coder_script") continue;
    for (const instance of resource.instances) {
      const attrs = instance.attributes as Record<string, unknown>;
      byDisplayName[attrs.display_name as string] = attrs.script as string;
    }
  }
  const install = byDisplayName["Cursor worker: Install Script"];
  const start = byDisplayName["Cursor worker: Start Script"];
  if (!install || !start) {
    throw new Error(
      `expected install and start scripts, found ${Object.keys(byDisplayName)}`,
    );
  }
  return { install, start };
};

const stubBinary = async (id: string, path: string, body: string) => {
  await writeFileContainer(id, path, `#!/usr/bin/env bash\n${body}\n`, {
    user: "root",
  });
  const chmod = await execContainer(id, ["chmod", "755", path]);
  expect(chmod.exitCode).toBe(0);
};

// Installs a fake Cursor CLI whose body is the given shell snippet.
const stubAgent = (id: string, body: string) =>
  stubBinary(id, "/usr/local/bin/agent", body);

// Runs the install step then the start step, as coder-utils orders them
// on the agent, and returns both results.
const runScripts = async (id: string, scripts: Scripts, env: string[]) => {
  const install = await execContainer(id, [
    "env",
    ...env,
    "bash",
    "-c",
    scripts.install,
  ]);
  expect(install.exitCode).toBe(0);
  const start = await execContainer(id, [
    "env",
    ...env,
    "bash",
    "-c",
    scripts.start,
  ]);
  return { install, start };
};

const runDispatched = (id: string, scripts: Scripts) =>
  runScripts(id, scripts, DISPATCH_ENV);

const readState = async (id: string) =>
  (await readFileContainer(id, STATE_FILE)).trim();

// The supervisor writes terminal state after the worker exits; poll rather
// than sleep a fixed amount.
const waitForState = async (id: string, pattern: RegExp, timeoutMs = 5000) => {
  const deadline = Date.now() + timeoutMs;
  let last = "";
  while (Date.now() < deadline) {
    last = await readState(id);
    if (pattern.test(last)) {
      return last;
    }
    await Bun.sleep(200);
  }
  throw new Error(
    `state never matched ${pattern}; last was ${JSON.stringify(last)}`,
  );
};

setDefaultTimeout(60 * 1000);

describe("agent-relay-cursor", () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("idles when no credential is set", async () => {
    const { id, scripts } = await setup({ install_cli: "false" });
    // No AGENT_RELAY_CURSOR_TOKEN: a workspace a human created by hand.
    const { start } = await runScripts(id, scripts, []);
    expect(start.exitCode).toBe(0);
    expect(start.stdout).toContain("created manually, not by Agent Relay");
    expect(await readState(id)).toBe("idle");
  });

  it("keeps terminal state across a restart without a credential", async () => {
    // The credential is ephemeral, so an agent restart after the worker
    // finished runs the start step with no credential. That must not
    // rewrite "done 3" as "idle", which the relay reads as never dispatched.
    const { id, scripts } = await setup({ install_cli: "false" });
    await execContainer(id, ["mkdir", "-p", MODULE_DIR]);
    await writeFileContainer(id, STATE_FILE, "done 3\n", { user: "root" });
    const { start } = await runScripts(id, scripts, []);
    expect(start.exitCode).toBe(0);
    expect(await readState(id)).toBe("done 3");
  });

  // An agent restart inside the same build re-runs the start step with the
  // credential still set and the previous run's state on disk.
  describe("agent restart with a credential", () => {
    const seedState = async (id: string, state: string) => {
      await execContainer(id, ["mkdir", "-p", MODULE_DIR]);
      await writeFileContainer(id, STATE_FILE, `${state}\n`, { user: "root" });
    };
    const workerCount = async (id: string) => {
      // pgrep -f would match the counting shell itself; read /proc and
      // count processes whose argv starts with the stub CLI.
      const out = await execContainer(id, [
        "sh",
        "-c",
        'n=0; for p in /proc/[0-9]*; do a=$(tr "\\0" " " <"$p/cmdline" 2>/dev/null); case "$a" in "bash /usr/local/bin/agent worker "*) n=$((n+1));; esac; done; echo $n',
      ]);
      return Number(out.stdout.trim());
    };
    const statusOf = async (id: string, statusScript: string) =>
      (await execContainer(id, ["bash", "-c", statusScript])).stdout.trim();

    it("does not restart after a terminal state", async () => {
      const { id, scripts } = await setup();
      await stubAgent(id, "sleep 30");
      await seedState(id, "done 3");
      const { start } = await runDispatched(id, scripts);
      expect(start.exitCode).toBe(0);
      expect(start.stdout).toContain("not restarting");
      expect(await readState(id)).toBe("done 3");
      expect(await workerCount(id)).toBe(0);
    });

    it("leaves a live worker alone instead of launching a second one", async () => {
      const { id, scripts, statusScript } = await setup();
      await stubAgent(id, "sleep 30");
      const first = await runDispatched(id, scripts);
      expect(first.start.exitCode).toBe(0);
      const state = await readState(id);
      expect(state).toMatch(/^working \d+$/);

      const second = await runDispatched(id, scripts);
      expect(second.start.exitCode).toBe(0);
      expect(second.start.stdout).toContain("already running");
      expect(await readState(id)).toBe(state);
      expect(await workerCount(id)).toBe(1);
      expect(await statusOf(id, statusScript)).toBe("working");
    });

    it("reports a reused pid as orphaned rather than working", async () => {
      // kill -0 alone would trust any live pid; the cmdline check must
      // reject one that is not our worker.
      const { id, scripts, statusScript } = await setup();
      await stubAgent(id, "sleep 30");
      const sleeper = await execContainer(id, [
        "sh",
        "-c",
        "sleep 60 >/dev/null 2>&1 & echo $!",
      ]);
      await seedState(id, `working ${sleeper.stdout.trim()}`);
      expect(await statusOf(id, statusScript)).toBe("orphaned");

      const { start } = await runDispatched(id, scripts);
      expect(start.exitCode).toBe(0);
      expect(start.stdout).toContain("gone without recording an exit");
      expect(await workerCount(id)).toBe(0);
    });

    it("starts fresh from a stale pending state", async () => {
      // A previous start that died before its supervisor wrote anything.
      const { id, scripts } = await setup();
      await stubAgent(id, "sleep 30");
      await seedState(id, "pending");
      const { start } = await runDispatched(id, scripts);
      expect(start.exitCode).toBe(0);
      expect(await readState(id)).toMatch(/^working \d+$/);
      expect(await workerCount(id)).toBe(1);
    });
  });

  it("reports runner-agent-missing when the CLI is absent", async () => {
    const { id, scripts } = await setup({ install_cli: "false" });
    const { install, start } = await runDispatched(id, scripts);
    expect(install.stdout).toContain("expecting 'agent' to be in the image");
    expect(start.exitCode).toBe(1);
    // coder-utils merges stderr into the tee'd log.
    expect(start.stdout).toContain(
      "The worker binary 'agent' is not available",
    );
    expect(await readState(id)).toBe("failed runner-agent-missing");
  });

  it("finds a bring-your-own CLI in ~/.local/bin when install_cli is false", async () => {
    // The official installer's location; the module must look there even
    // when it did not run the installer itself.
    const { id, scripts } = await setup({ install_cli: "false" });
    await execContainer(id, ["mkdir", "-p", "/root/.local/bin"]);
    await stubBinary(id, "/root/.local/bin/agent", "sleep 30");
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode, start.stdout).toBe(0);
    expect(await readState(id)).toMatch(/^working \d+$/);
  });

  it("skips the download when the CLI is already present", async () => {
    // install_cli defaults to true; a binary on PATH must short-circuit it.
    const { id, scripts } = await setup();
    await stubAgent(id, "sleep 30");
    const { install, start } = await runDispatched(id, scripts);
    expect(install.stdout).toContain(
      "Cursor CLI already present; skipping the install.",
    );
    expect(install.stdout).not.toContain("installing the latest release");
    expect(start.exitCode).toBe(0);
    expect(await readState(id)).toMatch(/^working \d+$/);
  });

  it("keeps scripts and logs under the module directory", async () => {
    const { id, scripts } = await setup();
    await stubAgent(id, "sleep 30");
    await runDispatched(id, scripts);
    for (const file of [
      "scripts/install.sh",
      "scripts/start.sh",
      "logs/install.log",
      "logs/start.log",
      "logs/worker.log",
      "scripts/supervise.sh",
      "worker-state",
    ]) {
      const exists = await execContainer(id, [
        "test",
        "-e",
        `${MODULE_DIR}/${file}`,
      ]);
      expect(exists.exitCode, file).toBe(0);
    }
    const startLog = await readFileContainer(
      id,
      `${MODULE_DIR}/logs/start.log`,
    );
    expect(startLog).toContain("Starting Cursor worker");
  });

  it("starts the worker detached with the pool arguments", async () => {
    const { id, scripts } = await setup();
    await stubAgent(id, 'printf "%s\\n" "$@" >/tmp/agent-args; sleep 30');
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode).toBe(0);
    expect(start.stdout).toContain("Starting Cursor worker (detached)...");

    const args = (await readFileContainer(id, "/tmp/agent-args")).split("\n");
    expect(args[0]).toBe("worker");
    expect(args).toContain("--pool");
    expect(args[args.indexOf("--pool") + 1]).toBe(POOL_NAME);
    expect(args).toContain("--idle-release-timeout");
    expect(args[args.indexOf("--idle-release-timeout") + 1]).toBe("600");
    // The metacharacters in the pool name must not have executed.
    const injected = await execContainer(id, ["test", "-e", "/tmp/injected"]);
    expect(injected.exitCode).not.toBe(0);
    // The token reaches the worker as --auth-token, not as an API key.
    expect(args[args.indexOf("--auth-token") + 1]).toBe("test-user-token");
    expect(args).toContain("start");
    expect(args).not.toContain("--computer-use");

    // The supervisor file on disk must reference the variable, never
    // carry the token itself.
    const supervisor = await readFileContainer(
      id,
      `${MODULE_DIR}/scripts/supervise.sh`,
    );
    expect(supervisor).toContain('--auth-token "$AGENT_RELAY_CURSOR_TOKEN"');
    expect(supervisor).not.toContain("test-user-token");
    // Parameter values are likewise read from the environment, never
    // written into the file where they would be parsed as shell.
    expect(supervisor).toContain('--pool "$AGENT_RELAY_CURSOR_POOL_NAME"');
    expect(supervisor).not.toContain(POOL_NAME);

    // The worker id keeps the Cursor CLI's own env var name.
    const env = await execContainer(id, [
      "sh",
      "-c",
      "cat /proc/$(pgrep -f 'agent worker' | head -1)/environ | tr '\\0' '\\n'",
    ]);
    expect(env.stdout).toContain("CURSOR_AGENT_WORKER_ID=worker-123");
    expect(env.stdout).not.toContain("CURSOR_API_KEY=");
  });

  it("hands a shared service-account key over as CURSOR_API_KEY", async () => {
    // insecure_shared_token pools stamp the team key; the CLI only
    // accepts it as an API key, so --auth-token must be absent and the
    // key must reach the worker's environment.
    const { id, scripts } = await setup({ credential_kind: "api_key" });
    await stubAgent(
      id,
      'printf "%s\\n" "$@" >/tmp/agent-args; printf "%s" "$CURSOR_API_KEY" >/tmp/agent-api-key; sleep 30',
    );
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode).toBe(0);
    const args = (await readFileContainer(id, "/tmp/agent-args")).split("\n");
    expect(args).not.toContain("--auth-token");
    expect(args).toContain("--pool");
    expect(await readFileContainer(id, "/tmp/agent-api-key")).toBe(
      "test-user-token",
    );
    // The key is still read from the environment at run time, never
    // written into the supervisor.
    const supervisor = await readFileContainer(
      id,
      `${MODULE_DIR}/scripts/supervise.sh`,
    );
    expect(supervisor).toContain(
      'export CURSOR_API_KEY="$AGENT_RELAY_CURSOR_TOKEN"',
    );
    expect(supervisor).not.toContain("test-user-token");
  });

  it("passes --computer-use when enabled", async () => {
    const { id, scripts } = await setup({ computer_use: "true" });
    await stubAgent(id, 'printf "%s\\n" "$@" >/tmp/agent-args; sleep 30');
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode).toBe(0);
    const args = (await readFileContainer(id, "/tmp/agent-args")).split("\n");
    expect(args).toContain("--computer-use");
  });

  it("records the exit code when the worker exits", async () => {
    const { id, scripts } = await setup();
    await stubAgent(id, "exit 3");
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode).toBe(0);
    expect(await waitForState(id, /^done \d+$/)).toBe("done 3");
  });

  it("uses cli_binary and state_file overrides", async () => {
    const { id, scripts } = await setup({
      cli_binary: "/opt/cursor/agent",
      state_file: "/var/lib/relay/state",
    });
    await execContainer(id, ["mkdir", "-p", "/opt/cursor"]);
    await stubBinary(id, "/opt/cursor/agent", "sleep 30");
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode).toBe(0);
    const state = (await readFileContainer(id, "/var/lib/relay/state")).trim();
    expect(state).toMatch(/^working \d+$/);
    // Overriding state_file moves only the state; the supervisor stays
    // under the module directory as the README documents.
    const supervisor = await execContainer(id, [
      "test",
      "-e",
      `${MODULE_DIR}/scripts/supervise.sh`,
    ]);
    expect(supervisor.exitCode).toBe(0);
    const escaped = await execContainer(id, [
      "test",
      "-e",
      "/var/lib/relay/supervise.sh",
    ]);
    expect(escaped.exitCode).not.toBe(0);
  });

  it("treats serving_log_pattern as data, not shell or regex", async () => {
    // A pattern carrying shell metacharacters must neither execute nor be
    // read as a regex; it is matched as a fixed string against the log.
    const pattern = 'x"; touch /tmp/PWNED; "';
    const { id, scripts, statusScript } = await setup({
      serving_log_pattern: pattern,
    });
    await stubAgent(id, "sleep 30");
    await runDispatched(id, scripts);
    expect(await readState(id)).toMatch(/^working \d+$/);

    const status = (log: string) =>
      execContainer(id, [
        "sh",
        "-c",
        `printf '%s\\n' "$1" >${MODULE_DIR}/logs/worker.log && bash -c "$2"`,
        "sh",
        log,
        statusScript,
      ]);

    const noMatch = await status("Waiting for work");
    expect(noMatch.exitCode, noMatch.stderr).toBe(0);
    expect(noMatch.stdout.trim()).toBe("working");

    // Only the literal pattern flips the state to serving.
    const match = await status(`log line ${pattern} tail`);
    expect(match.exitCode, match.stderr).toBe(0);
    expect(match.stdout.trim()).toBe("serving");

    const pwned = await execContainer(id, ["test", "-e", "/tmp/PWNED"]);
    expect(pwned.exitCode).not.toBe(0);
  });
});
