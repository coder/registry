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

// The runner script is exercised inside a throwaway container with a stub
// `claude` binary standing in for the Claude Code CLI, so the supervisor
// lifecycle the relay's reaper depends on (idle, working, done, failed) is
// observed rather than grepped for. The real installer and the real runner
// are out of scope: both need the network and Anthropic's side.

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

const STATE_FILE = "/tmp/agent-relay/runner-state";
const DISPATCH_ENV = [
  "SELF_HOSTED_RUNNER_POOL_SECRET=test-work-order-jwt",
  "SELF_HOSTED_RUNNER_LOCK_TO_ACCOUNT=acct-123",
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

// Installs a fake Claude Code CLI whose body is the given shell snippet.
const stubClaude = async (id: string, body: string) => {
  await writeFileContainer(
    id,
    "/usr/local/bin/claude",
    `#!/usr/bin/env bash\n${body}\n`,
    { user: "root" },
  );
  const chmod = await execContainer(id, [
    "chmod",
    "755",
    "/usr/local/bin/claude",
  ]);
  expect(chmod.exitCode).toBe(0);
};

const runDispatched = (id: string, script: string) =>
  execContainer(id, ["env", ...DISPATCH_ENV, "bash", "-c", script]);

const readState = async (id: string) =>
  (await readFileContainer(id, STATE_FILE)).trim();

// The supervisor writes terminal state after the runner exits; poll rather
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

describe("agent-relay-claude-code", () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("idles when no credential is set", async () => {
    const { id, script } = await setup();
    // No SELF_HOSTED_RUNNER_POOL_SECRET: a workspace a human created by hand.
    const exec = await execContainer(id, ["bash", "-c", script]);
    expect(exec.exitCode).toBe(0);
    expect(exec.stdout).toContain("created manually, not by Agent Relay");
    expect(await readState(id)).toBe("idle");
  });

  it("reports runner-agent-missing when the CLI is absent", async () => {
    const { id, script } = await setup({ install_cli: "false" });
    const exec = await runDispatched(id, script);
    expect(exec.exitCode).toBe(1);
    expect(exec.stderr).toContain(
      "The runner binary 'claude' is not available",
    );
    expect(await readState(id)).toBe("failed runner-agent-missing");
  });

  it("skips the download when the CLI is already present", async () => {
    // install_cli defaults to true; a binary on PATH must short-circuit it.
    const { id, script } = await setup();
    await stubClaude(id, "sleep 30");
    const exec = await runDispatched(id, script);
    expect(exec.exitCode).toBe(0);
    expect(exec.stdout).toContain(
      "Claude Code CLI already present; skipping the install.",
    );
    expect(exec.stdout).not.toContain("installing the latest release");
    expect(await readState(id)).toMatch(/^working \d+$/);
  });

  it("starts the runner detached through the permissions wrapper", async () => {
    const { id, script } = await setup();
    await stubClaude(id, 'printf "%s\\n" "$@" >/tmp/claude-args; sleep 30');
    const exec = await runDispatched(id, script);
    expect(exec.exitCode).toBe(0);
    expect(exec.stdout).toContain(
      "Starting Claude Code self-hosted runner (detached)...",
    );

    const args = (await readFileContainer(id, "/tmp/claude-args")).split("\n");
    expect(args[0]).toBe("self-hosted-runner");
    expect(args[args.indexOf("--capacity") + 1]).toBe("1");
    expect(args[args.indexOf("--exec-path") + 1]).toBe(
      "/root/.claude/wrapper.sh",
    );

    // The wrapper is what forces bypassPermissions on every session.
    const wrapper = await readFileContainer(id, "/root/.claude/wrapper.sh");
    expect(wrapper).toContain("--permission-mode bypassPermissions");

    // The runner inherits the CLI's own env var names, not the relay's.
    const env = await execContainer(id, [
      "sh",
      "-c",
      "cat /proc/$(pgrep -f 'claude self-hosted-runner' | head -1)/environ | tr '\\0' '\\n'",
    ]);
    expect(env.stdout).toContain(
      "SELF_HOSTED_RUNNER_POOL_SECRET=test-work-order-jwt",
    );
    expect(env.stdout).toContain("SELF_HOSTED_RUNNER_LOCK_TO_ACCOUNT=acct-123");
  });

  it("records the exit code when the runner exits", async () => {
    const { id, script } = await setup();
    await stubClaude(id, "exit 3");
    const exec = await runDispatched(id, script);
    expect(exec.exitCode).toBe(0);
    expect(await waitForState(id, /^done \d+$/)).toBe("done 3");
  });

  it("uses cli_binary and state_file overrides", async () => {
    const { id, script } = await setup({
      cli_binary: "/opt/claude/claude",
      state_file: "/var/lib/relay/state",
    });
    await execContainer(id, ["mkdir", "-p", "/opt/claude"]);
    await writeFileContainer(
      id,
      "/opt/claude/claude",
      "#!/usr/bin/env bash\nsleep 30\n",
      { user: "root" },
    );
    await execContainer(id, ["chmod", "755", "/opt/claude/claude"]);
    const exec = await runDispatched(id, script);
    expect(exec.exitCode).toBe(0);
    const state = (await readFileContainer(id, "/var/lib/relay/state")).trim();
    expect(state).toMatch(/^working \d+$/);
  });
});
