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
// throwaway container with a stub `claude` binary standing in for the
// Claude Code CLI, so the supervisor lifecycle the relay's reaper depends
// on (idle, working, done, failed) is observed rather than grepped for.
// The real installer and the real runner are out of scope: both need the
// network and Anthropic's side. `coder` is stubbed so the `coder exp sync`
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
const MODULE_DIR = "/root/.coder-modules/coder/agent-relay-claude-code";
const STATE_FILE = `${MODULE_DIR}/runner-state`;
const DISPATCH_ENV = [
  "SELF_HOSTED_RUNNER_POOL_SECRET=test-work-order-jwt",
  "SELF_HOSTED_RUNNER_LOCK_TO_ACCOUNT=acct-123",
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
  const install = byDisplayName["Claude Code runner: Install Script"];
  const start = byDisplayName["Claude Code runner: Start Script"];
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

// Installs a fake Claude Code CLI whose body is the given shell snippet.
const stubClaude = (id: string, body: string) =>
  stubBinary(id, "/usr/local/bin/claude", body);

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
    const { id, scripts } = await setup({ install_cli: "false" });
    // No SELF_HOSTED_RUNNER_POOL_SECRET: a workspace a human created by hand.
    const { start } = await runScripts(id, scripts, []);
    expect(start.exitCode).toBe(0);
    expect(start.stdout).toContain("created manually, not by Agent Relay");
    expect(await readState(id)).toBe("idle");
  });

  it("keeps terminal state across a restart without a credential", async () => {
    // The credential is ephemeral, so an agent restart after the runner
    // finished runs the start step with no credential. That must not
    // rewrite "done 3" as "idle", which the relay reads as never dispatched.
    const { id, scripts } = await setup({ install_cli: "false" });
    await execContainer(id, ["mkdir", "-p", MODULE_DIR]);
    await writeFileContainer(id, STATE_FILE, "done 3\n", { user: "root" });
    const { start } = await runScripts(id, scripts, []);
    expect(start.exitCode).toBe(0);
    expect(await readState(id)).toBe("done 3");
  });

  it("reports runner-agent-missing when the CLI is absent", async () => {
    const { id, scripts } = await setup({ install_cli: "false" });
    const { install, start } = await runDispatched(id, scripts);
    expect(install.stdout).toContain("expecting 'claude' to be in the image");
    expect(start.exitCode).toBe(1);
    // coder-utils merges stderr into the tee'd log.
    expect(start.stdout).toContain(
      "The runner binary 'claude' is not available",
    );
    expect(await readState(id)).toBe("failed runner-agent-missing");
  });

  it("finds a bring-your-own CLI in ~/.local/bin when install_cli is false", async () => {
    // The official installer's location; the module must look there even
    // when it did not run the installer itself.
    const { id, scripts } = await setup({ install_cli: "false" });
    await execContainer(id, ["mkdir", "-p", "/root/.local/bin"]);
    await stubBinary(id, "/root/.local/bin/claude", "sleep 30");
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode, start.stdout).toBe(0);
    expect(await readState(id)).toMatch(/^working \d+$/);
  });

  it("skips the download when the CLI is already present", async () => {
    // install_cli defaults to true; a binary on PATH must short-circuit it.
    const { id, scripts } = await setup();
    await stubClaude(id, "sleep 30");
    const { install, start } = await runDispatched(id, scripts);
    expect(install.stdout).toContain(
      "Claude Code CLI already present; skipping the install.",
    );
    expect(install.stdout).not.toContain("installing the latest release");
    expect(start.exitCode).toBe(0);
    expect(await readState(id)).toMatch(/^working \d+$/);
  });

  it("keeps scripts and logs under the module directory", async () => {
    const { id, scripts } = await setup();
    await stubClaude(id, "sleep 30");
    await runDispatched(id, scripts);
    for (const file of [
      "scripts/install.sh",
      "scripts/start.sh",
      "logs/install.log",
      "logs/start.log",
      "logs/runner.log",
      "supervise.sh",
      "runner-state",
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
    expect(startLog).toContain("Starting Claude Code self-hosted runner");
  });

  it("starts the runner detached through the permissions wrapper", async () => {
    const { id, scripts } = await setup();
    await stubClaude(id, 'printf "%s\\n" "$@" >/tmp/claude-args; sleep 30');
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode).toBe(0);
    expect(start.stdout).toContain(
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

    // Run the wrapper as root against a stub that enforces the CLI's
    // guard: bypassPermissions is refused for uid 0 unless IS_SANDBOX=1.
    // The text assertion above cannot catch a missing IS_SANDBOX.
    await stubBinary(
      id,
      "/usr/local/bin/claude-session",
      [
        'if [ "$(id -u)" = 0 ] && [ "${IS_SANDBOX:-}" != 1 ]; then',
        '  echo "--dangerously-skip-permissions cannot be used with root/sudo privileges" >&2',
        "  exit 1",
        "fi",
        'printf "%s\\n" "$@"',
      ].join("\n"),
    );
    const session = await execContainer(id, [
      "env",
      "CLAUDE_RUNNER_CLAUDE_BIN=/usr/local/bin/claude-session",
      "/root/.claude/wrapper.sh",
      "--print",
      "hi",
    ]);
    expect(session.exitCode, session.stderr).toBe(0);
    expect(session.stdout.split("\n")).toEqual([
      "--print",
      "hi",
      "--permission-mode",
      "bypassPermissions",
      "",
    ]);

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
    const { id, scripts } = await setup();
    await stubClaude(id, "exit 3");
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode).toBe(0);
    expect(await waitForState(id, /^done \d+$/)).toBe("done 3");
  });

  it("uses cli_binary and state_file overrides", async () => {
    const { id, scripts } = await setup({
      cli_binary: "/opt/claude/claude",
      state_file: "/var/lib/relay/state",
    });
    await execContainer(id, ["mkdir", "-p", "/opt/claude"]);
    await stubBinary(id, "/opt/claude/claude", "sleep 30");
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode).toBe(0);
    const state = (await readFileContainer(id, "/var/lib/relay/state")).trim();
    expect(state).toMatch(/^working \d+$/);
  });

  it("treats serving_log_pattern as data, not shell or regex", async () => {
    // A pattern carrying shell metacharacters must neither execute nor be
    // read as a regex; it is matched as a fixed string against the log.
    const pattern = 'x"; touch /tmp/PWNED; "';
    const { id, scripts, statusScript } = await setup({
      serving_log_pattern: pattern,
    });
    await stubClaude(id, "sleep 30");
    await runDispatched(id, scripts);
    expect(await readState(id)).toMatch(/^working \d+$/);

    const status = (log: string) =>
      execContainer(id, [
        "sh",
        "-c",
        `printf '%s\\n' "$1" >${MODULE_DIR}/logs/runner.log && bash -c "$2"`,
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
