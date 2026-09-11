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
  findResourceInstance,
  readFileContainer,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  writeFileContainer,
} from "~test";

// The worker script is exercised inside a throwaway container with a stub
// `agent` binary standing in for the Cursor CLI, so the supervisor lifecycle
// the relay's reaper depends on (idle, working, done, failed) is observed
// rather than grepped for. The real installer and the real worker are out
// of scope: both need the network and Cursor's side.

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

const STATE_FILE = "/tmp/agent-relay/worker-state";
const DISPATCH_ENV = [
  "CURSOR_API_KEY=test-service-account-key",
  "CURSOR_AGENT_WORKER_ID=worker-123",
];

const setup = async (vars: Record<string, string> = {}) => {
  const state = await runTerraformApply(import.meta.dir, {
    agent_id: "foo",
    ...vars,
  });
  const script = findResourceInstance(state, "coder_script").script;
  const id = await runContainer("lorello/alpine-bash");
  registerCleanup(async () => {
    await removeContainer(id);
  });
  return { id, script };
};

// Installs a fake Cursor CLI whose body is the given shell snippet.
const stubAgent = async (id: string, body: string) => {
  await writeFileContainer(
    id,
    "/usr/local/bin/agent",
    `#!/usr/bin/env bash\n${body}\n`,
    { user: "root" },
  );
  const chmod = await execContainer(id, [
    "chmod",
    "755",
    "/usr/local/bin/agent",
  ]);
  expect(chmod.exitCode).toBe(0);
};

const runDispatched = (id: string, script: string) =>
  execContainer(id, ["env", ...DISPATCH_ENV, "bash", "-c", script]);

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
    const { id, script } = await setup();
    // No CURSOR_API_KEY: this is a workspace a human created by hand.
    const exec = await execContainer(id, ["bash", "-c", script]);
    expect(exec.exitCode).toBe(0);
    expect(exec.stdout).toContain("created manually, not by Agent Relay");
    expect(await readState(id)).toBe("idle");
  });

  it("reports runner-agent-missing when the CLI is absent", async () => {
    const { id, script } = await setup({ install_cli: "false" });
    const exec = await runDispatched(id, script);
    expect(exec.exitCode).toBe(1);
    expect(exec.stderr).toContain("The worker binary 'agent' is not available");
    expect(await readState(id)).toBe("failed runner-agent-missing");
  });

  it("skips the download when the CLI is already present", async () => {
    // install_cli defaults to true; a binary on PATH must short-circuit it.
    const { id, script } = await setup();
    await stubAgent(id, "sleep 30");
    const exec = await runDispatched(id, script);
    expect(exec.exitCode).toBe(0);
    expect(exec.stdout).toContain(
      "Cursor CLI already present; skipping the install.",
    );
    expect(exec.stdout).not.toContain("installing the latest release");
    expect(await readState(id)).toMatch(/^working \d+$/);
  });

  it("starts the worker detached with the pool arguments", async () => {
    const { id, script } = await setup();
    await stubAgent(id, 'printf "%s\\n" "$@" >/tmp/agent-args; sleep 30');
    const exec = await runDispatched(id, script);
    expect(exec.exitCode).toBe(0);
    expect(exec.stdout).toContain("Starting Cursor worker (detached)...");

    const args = (await readFileContainer(id, "/tmp/agent-args")).split("\n");
    expect(args[0]).toBe("worker");
    expect(args).toContain("--pool");
    expect(args).toContain("--idle-release-timeout");
    // The parameter default when Agent Relay has not stamped a value.
    expect(args[args.indexOf("--idle-release-timeout") + 1]).toBe("600");
    expect(args).toContain("start");
    expect(args).not.toContain("--computer-use");

    // The worker inherits the CLI's own env var names, not the relay's.
    const env = await execContainer(id, [
      "sh",
      "-c",
      "cat /proc/$(pgrep -f 'agent worker' | head -1)/environ | tr '\\0' '\\n'",
    ]);
    expect(env.stdout).toContain("CURSOR_API_KEY=test-service-account-key");
    expect(env.stdout).toContain("CURSOR_AGENT_WORKER_ID=worker-123");
  });

  it("passes --computer-use when enabled", async () => {
    const { id, script } = await setup({ computer_use: "true" });
    await stubAgent(id, 'printf "%s\\n" "$@" >/tmp/agent-args; sleep 30');
    const exec = await runDispatched(id, script);
    expect(exec.exitCode).toBe(0);
    const args = (await readFileContainer(id, "/tmp/agent-args")).split("\n");
    expect(args).toContain("--computer-use");
  });

  it("records the exit code when the worker exits", async () => {
    const { id, script } = await setup();
    await stubAgent(id, "exit 3");
    const exec = await runDispatched(id, script);
    expect(exec.exitCode).toBe(0);
    expect(await waitForState(id, /^done \d+$/)).toBe("done 3");
  });

  it("uses cli_binary and state_file overrides", async () => {
    const { id, script } = await setup({
      cli_binary: "/opt/cursor/agent",
      state_file: "/var/lib/relay/state",
    });
    await execContainer(id, ["mkdir", "-p", "/opt/cursor"]);
    await writeFileContainer(
      id,
      "/opt/cursor/agent",
      "#!/usr/bin/env bash\nsleep 30\n",
      { user: "root" },
    );
    await execContainer(id, ["chmod", "755", "/opt/cursor/agent"]);
    const exec = await runDispatched(id, script);
    expect(exec.exitCode).toBe(0);
    const state = (await readFileContainer(id, "/var/lib/relay/state")).trim();
    expect(state).toMatch(/^working \d+$/);
  });
});
