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
// pre-install and stop render the same cleanup template. Stop must not
// publish a new launch marker. The real installer and worker are out of
// scope: both need the network and Cursor's side.
// `coder` is stubbed so the `coder exp sync` ordering calls succeed
// without a control plane.

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
const TOKEN_FILE = `${MODULE_DIR}/worker-token`;
const SUPERVISORS_DIR = `${MODULE_DIR}/supervisors`;
const WORKERS_DIR = `${MODULE_DIR}/workers`;
const CLEANUP_MARKER = `${MODULE_DIR}/cleanup-complete`;
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
  const attachedScript = state.outputs.session_attached_metadata_script
    .value as string;
  const id = await runContainer("lorello/alpine-bash");
  registerCleanup(async () => {
    await removeContainer(id);
  });
  await stubBinary(id, "/usr/local/bin/coder", "exit 0");
  return { id, scripts, statusScript, attachedScript };
};

type Scripts = {
  preInstall: string;
  install: string;
  start: string;
  stop: string;
};

// coder-utils owns the coder_script resources; find ours by display name.
const collectScripts = (state: TerraformState): Scripts => {
  const byDisplayName: Record<string, string> = {};
  for (const resource of state.resources) {
    if (resource.type !== "coder_script") continue;
    for (const instance of resource.instances) {
      const attrs = instance.attributes as Record<string, unknown>;
      byDisplayName[attrs.display_name as string] = attrs.script as string;
      expect(attrs.run_on_stop, attrs.display_name as string).toBe(
        attrs.display_name === "Cursor worker: Stop Script",
      );
    }
  }
  const scripts = {
    preInstall: byDisplayName["Cursor worker: Pre-Install Script"],
    install: byDisplayName["Cursor worker: Install Script"],
    start: byDisplayName["Cursor worker: Start Script"],
    stop: byDisplayName["Cursor worker: Stop Script"],
  };
  if (Object.values(scripts).some((s) => !s)) {
    throw new Error(
      `expected pre-install, install, start, and stop scripts, found ${Object.keys(byDisplayName)}`,
    );
  }
  return scripts;
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

// Runs the pre-install, install, and start steps, as coder-utils orders
// them on the agent, and returns their results.
const runScripts = async (id: string, scripts: Scripts, env: string[]) => {
  const run = (script: string) =>
    execContainer(id, ["env", ...env, "bash", "-c", script]);
  const preInstall = await run(scripts.preInstall);
  expect(preInstall.exitCode, preInstall.stdout).toBe(0);
  const install = await run(scripts.install);
  expect(install.exitCode).toBe(0);
  const start = await run(scripts.start);
  return { preInstall, install, start };
};

const runDispatched = (id: string, scripts: Scripts) =>
  runScripts(id, scripts, DISPATCH_ENV);

const readState = async (id: string) =>
  (await readFileContainer(id, STATE_FILE)).trim();

const exists = async (id: string, path: string) =>
  (await execContainer(id, ["test", "-e", path])).exitCode === 0;

// Identity records in dir, as "<pid> <boot id> <starttime>" lines, plus
// any temp file a process left mid-write.
const recordsIn = async (id: string, dir: string) => {
  const out = await execContainer(id, [
    "sh",
    "-c",
    `for f in ${dir}/* ${dir}/.*.tmp; do [ -f "$f" ] && cat "$f"; done; true`,
  ]);
  return out.stdout.split("\n").filter((l) => l !== "");
};
const supervisorRecords = (id: string) => recordsIn(id, SUPERVISORS_DIR);
const workerRecords = (id: string) => recordsIn(id, WORKERS_DIR);
const allRecords = async (id: string) => [
  ...(await supervisorRecords(id)),
  ...(await workerRecords(id)),
];

// The pids of the one live supervisor and worker.
const liveIdentity = async (id: string) => {
  const [supervisor] = await supervisorRecords(id);
  const [worker] = await workerRecords(id);
  return {
    supervisorPid: supervisor.split(" ")[0],
    workerPid: worker.split(" ")[0],
  };
};

const starttimeOf = async (id: string, pid: string) =>
  (
    await execContainer(id, [
      "bash",
      "-c",
      `s=$(cat /proc/${pid}/stat); s=\${s##*) }; set -- $s; echo \${20}`,
    ])
  ).stdout.trim();

// True while pid is a live, non-zombie process. The container's init does
// not reap, so an exited orphan lingers as a zombie.
const processAlive = async (id: string, pid: string) => {
  const out = await execContainer(id, [
    "sh",
    "-c",
    `s=$(cat /proc/${pid}/stat 2>/dev/null) || exit 1; s=\${s##*) }; [ "\${s%% *}" != Z ]`,
  ]);
  return out.exitCode === 0;
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

const waitFor = async (
  check: () => Promise<boolean>,
  what: string,
  timeoutMs = 5000,
) => {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await check()) return;
    await Bun.sleep(200);
  }
  throw new Error(`timed out waiting for ${what}`);
};

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
    expect(start.stdout).toContain("No worker token in this build");
    expect(await readState(id)).toBe("idle");
  });

  it("reports idle after a restart without a credential, whatever ran before", async () => {
    // The credential is ephemeral, so an agent restart runs the start step
    // with no credential. No worker can run without a fresh one, and the
    // cleanup clears the previous run's state, so a stale "done 3" is
    // never reported as this run's.
    const { id, scripts } = await setup({ install_cli: "false" });
    await execContainer(id, ["mkdir", "-p", MODULE_DIR]);
    await writeFileContainer(id, STATE_FILE, "done 3\n", { user: "root" });
    const { start } = await runScripts(id, scripts, []);
    expect(start.exitCode).toBe(0);
    expect(await readState(id)).toBe("idle");
  });

  it("sets no coder_env for the worker token's variable", async () => {
    // The agent injects AGENT_RELAY_CURSOR_TOKEN from the workspace
    // secret. A coder_env of that name, as 0.x had, would put the token
    // back in Terraform state.
    const state = await runTerraformApply(import.meta.dir, { agent_id: "foo" });
    const envNames = state.resources
      .filter((resource) => resource.type === "coder_env")
      .flatMap((resource) =>
        resource.instances.map((instance) => instance.attributes.name),
      );
    expect(envNames).not.toContain("AGENT_RELAY_CURSOR_TOKEN");
  });

  it("removes a stale token before idling without cleanup or a credential", async () => {
    const { id, scripts } = await setup();
    await stubAgent(id, "sleep 120");
    const first = await runDispatched(id, scripts);
    expect(first.start.exitCode).toBe(0);
    const { supervisorPid, workerPid } = await liveIdentity(id);
    const previousId = (await readFileContainer(id, CLEANUP_MARKER)).trim();
    expect(await readFileContainer(id, TOKEN_FILE)).toBe("test-user-token");

    // The ephemeral credential was cleared, but pre-install did not run.
    const idle = await execContainer(id, ["bash", "-c", scripts.start]);
    expect(idle.exitCode).toBe(0);
    expect(await exists(id, TOKEN_FILE)).toBe(false);
    expect(await readState(id)).toBe("idle");
    expect((await readFileContainer(id, CLEANUP_MARKER)).trim()).not.toBe(
      previousId,
    );
    expect(await processAlive(id, workerPid)).toBe(true);

    // The previous supervisor is fenced from writing terminal state.
    await execContainer(id, ["kill", "-TERM", workerPid]);
    await waitFor(
      async () =>
        !(await supervisorRecords(id)).some((record) =>
          record.startsWith(`${supervisorPid} `),
        ),
      "previous supervisor exit",
    );
    expect(await readState(id)).toBe("idle");
    expect(await exists(id, TOKEN_FILE)).toBe(false);
  });

  // An agent restart inside the same build re-runs every step with the
  // credential still set, and the previous run's state, records, and
  // possibly its detached supervisor still around.
  describe("agent restart with a credential", () => {
    const seedState = async (id: string, state: string) => {
      await execContainer(id, ["mkdir", "-p", MODULE_DIR]);
      await writeFileContainer(id, STATE_FILE, `${state}\n`, { user: "root" });
    };
    const statusOf = async (id: string, statusScript: string) =>
      (await execContainer(id, ["bash", "-c", statusScript])).stdout.trim();
    // An unrelated live process, and its real /proc starttime.
    const startSleeper = async (id: string) => {
      const out = await execContainer(id, [
        "bash",
        "-c",
        'sleep 60 >/dev/null 2>&1 & s=$(cat /proc/$!/stat); s=${s##*) }; set -- $s; echo "$! ${20}"',
      ]);
      const [pid, starttime] = out.stdout.trim().split(" ");
      return { pid, starttime };
    };
    const bootId = async (id: string) =>
      (await readFileContainer(id, "/proc/sys/kernel/random/boot_id")).trim();

    it("starts a fresh worker after a terminal state", async () => {
      const { id, scripts } = await setup();
      await stubAgent(id, "sleep 30");
      await seedState(id, "done 3");
      const { start } = await runDispatched(id, scripts);
      expect(start.exitCode).toBe(0);
      expect(await readState(id)).toMatch(/^working \d+$/);
      expect(await workerCount(id)).toBe(1);
    });

    it("replaces a live worker instead of running a second one", async () => {
      const { id, scripts, statusScript } = await setup();
      await stubAgent(id, "sleep 30");
      const first = await runDispatched(id, scripts);
      expect(first.start.exitCode).toBe(0);
      const firstState = await readState(id);
      expect(firstState).toMatch(/^working \d+$/);

      // Both processes published their identity before the CLI ran.
      expect(await supervisorRecords(id)).toHaveLength(1);
      expect(await workerRecords(id)).toHaveLength(1);
      const { supervisorPid, workerPid } = await liveIdentity(id);
      expect(firstState).toBe(`working ${workerPid}`);
      for (const record of await allRecords(id)) {
        const [pid, recordedBoot, recordedStart] = record.split(" ");
        expect(recordedBoot).toBe(await bootId(id));
        // The worker's starttime survives the exec into the CLI.
        expect(recordedStart).toBe(await starttimeOf(id, pid));
      }

      const second = await runDispatched(id, scripts);
      expect(second.preInstall.stdout).toContain(
        `Stopping previous Cursor supervisor (pid ${supervisorPid})`,
      );
      expect(second.preInstall.stdout).toContain(
        `Stopping previous Cursor worker (pid ${workerPid})`,
      );
      expect(second.start.exitCode, second.start.stdout).toBe(0);
      expect(await processAlive(id, supervisorPid)).toBe(false);
      expect(await processAlive(id, workerPid)).toBe(false);
      const secondState = await readState(id);
      expect(secondState).toMatch(/^working \d+$/);
      expect(secondState).not.toBe(firstState);
      expect(await workerCount(id)).toBe(1);
      const after = await liveIdentity(id);
      expect(after.supervisorPid).not.toBe(supervisorPid);
      expect(await allRecords(id)).toHaveLength(2);
      expect(await statusOf(id, statusScript)).toBe("working");
    });

    it("stops a worker whose supervisor was SIGKILLed, so the next start runs only one", async () => {
      const { id, scripts } = await setup();
      await stubAgent(id, "sleep 30");
      const first = await runDispatched(id, scripts);
      expect(first.start.exitCode).toBe(0);
      const { supervisorPid, workerPid } = await liveIdentity(id);

      // No trap runs on SIGKILL: the worker outlives its supervisor, and
      // only its own record still tracks it.
      await execContainer(id, ["kill", "-KILL", supervisorPid]);
      await waitFor(
        async () => !(await processAlive(id, supervisorPid)),
        "supervisor exit",
      );
      expect(await processAlive(id, workerPid)).toBe(true);
      expect(await workerCount(id)).toBe(1);

      const second = await runDispatched(id, scripts);
      expect(second.preInstall.stdout).toContain(
        `Stopping previous Cursor worker (pid ${workerPid})`,
      );
      expect(second.start.exitCode, second.start.stdout).toBe(0);
      expect(await processAlive(id, workerPid)).toBe(false);
      expect(await workerCount(id)).toBe(1);
      expect(await readState(id)).not.toBe(`working ${workerPid}`);
      // Only the new supervisor and worker are recorded.
      expect(await supervisorRecords(id)).toHaveLength(1);
      expect(await workerRecords(id)).toHaveLength(1);
      expect((await liveIdentity(id)).workerPid).not.toBe(workerPid);
    });

    it("never signals a pid whose identity does not match its record", async () => {
      // A recorded pid can be reused by an unrelated process, after the
      // supervisor exits or across a reboot. Only the boot id and the
      // /proc starttime together prove it is still the supervisor.
      const { id, scripts } = await setup();
      await stubAgent(id, "sleep 30");
      const reused = await startSleeper(id);
      const rebooted = await startSleeper(id);
      await execContainer(id, ["mkdir", "-p", SUPERVISORS_DIR]);
      await writeFileContainer(
        id,
        `${SUPERVISORS_DIR}/${reused.pid}.1`,
        `${reused.pid} ${await bootId(id)} 1\n`,
        { user: "root" },
      );
      await writeFileContainer(
        id,
        `${SUPERVISORS_DIR}/${rebooted.pid}.${rebooted.starttime}`,
        `${rebooted.pid} 00000000-0000-0000-0000-000000000000 ${rebooted.starttime}\n`,
        { user: "root" },
      );
      await writeFileContainer(
        id,
        `${SUPERVISORS_DIR}/garbage`,
        "not a pid\n",
        {
          user: "root",
        },
      );
      // The same rules hold for worker records.
      await execContainer(id, ["mkdir", "-p", WORKERS_DIR]);
      await writeFileContainer(
        id,
        `${WORKERS_DIR}/${reused.pid}.1`,
        `${reused.pid} ${await bootId(id)} 1\n`,
        { user: "root" },
      );

      const { preInstall, start } = await runDispatched(id, scripts);
      expect(preInstall.stdout).not.toContain("Stopping previous");
      expect(start.exitCode).toBe(0);
      expect(await processAlive(id, reused.pid)).toBe(true);
      expect(await processAlive(id, rebooted.pid)).toBe(true);
      // Mismatched identities are discarded; only the malformed record
      // remains alongside the new supervisor and worker records.
      expect(await supervisorRecords(id)).toHaveLength(2);
      expect(await workerRecords(id)).toHaveLength(1);
      expect(await exists(id, `${SUPERVISORS_DIR}/garbage`)).toBe(true);
      for (const record of await allRecords(id)) {
        expect(record).not.toContain(reused.pid + " ");
        expect(record).not.toContain(rebooted.pid + " ");
      }
      expect(await workerCount(id)).toBe(1);
    });

    it("reports a reused pid as orphaned, then starts fresh", async () => {
      // kill -0 alone would trust any live pid; the cmdline check must
      // reject one that is not our worker.
      const { id, scripts, statusScript } = await setup();
      await stubAgent(id, "sleep 30");
      const sleeper = await startSleeper(id);
      await seedState(id, `working ${sleeper.pid}`);
      expect(await statusOf(id, statusScript)).toBe("orphaned");

      const { start } = await runDispatched(id, scripts);
      expect(start.exitCode).toBe(0);
      expect(await readState(id)).toMatch(/^working \d+$/);
      expect(await readState(id)).not.toBe(`working ${sleeper.pid}`);
      expect(await workerCount(id)).toBe(1);
      expect(await processAlive(id, sleeper.pid)).toBe(true);
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

    it(
      "SIGKILLs verified processes that ignore TERM, then starts one worker",
      async () => {
        const { id, scripts } = await setup();
        await stubAgent(id, "trap '' TERM; sleep 60");
        const first = await runDispatched(id, scripts);
        expect(first.start.exitCode).toBe(0);
        const { supervisorPid, workerPid } = await liveIdentity(id);

        const second = await runDispatched(id, scripts);
        expect(second.preInstall.stdout).toContain(
          `Previous Cursor worker (pid ${workerPid}) did not stop within 10s; sending SIGKILL.`,
        );
        expect(second.start.exitCode, second.start.stdout).toBe(0);
        expect(await processAlive(id, workerPid)).toBe(false);
        expect(await processAlive(id, supervisorPid)).toBe(false);
        expect(await workerCount(id)).toBe(1);
        expect((await liveIdentity(id)).workerPid).not.toBe(workerPid);
        expect(await allRecords(id)).toHaveLength(2);
      },
      90 * 1000,
    );

    it("does not signal a pid from a different boot and publishes a new marker", async () => {
      const { id, scripts } = await setup();
      await stubAgent(id, "sleep 120");
      const first = await runDispatched(id, scripts);
      expect(first.start.exitCode).toBe(0);
      const oldId = (await readFileContainer(id, CLEANUP_MARKER)).trim();
      const sleeper = await startSleeper(id);
      await writeFileContainer(
        id,
        `${WORKERS_DIR}/${sleeper.pid}.${sleeper.starttime}`,
        `${sleeper.pid} invalid-boot ${sleeper.starttime}\n`,
        { user: "root" },
      );

      const second = await runDispatched(id, scripts);
      expect(second.start.exitCode, second.start.stdout).toBe(0);
      expect((await readFileContainer(id, CLEANUP_MARKER)).trim()).not.toBe(
        oldId,
      );
      expect(await processAlive(id, sleeper.pid)).toBe(true);
      expect(
        await exists(id, `${WORKERS_DIR}/${sleeper.pid}.${sleeper.starttime}`),
      ).toBe(false);
      expect(await workerCount(id)).toBe(1);
    });

    it("logs and keeps malformed records while starting a new generation", async () => {
      const { id, scripts } = await setup();
      await stubAgent(id, "sleep 120");
      await execContainer(id, ["mkdir", "-p", WORKERS_DIR]);
      const badRecord = `${WORKERS_DIR}/invalid`;
      await writeFileContainer(id, badRecord, "not a pid\n", { user: "root" });
      const result = await runDispatched(id, scripts);
      expect(result.preInstall.stdout).toContain(
        "Unverifiable Cursor worker record",
      );
      expect(result.start.exitCode).toBe(0);
      expect(await exists(id, badRecord)).toBe(true);
    });

    it(
      "publishes a fresh marker and starts even when a verified worker survives",
      async () => {
        const { id, scripts } = await setup();
        await stubAgent(id, "sleep 120");
        const first = await runDispatched(id, scripts);
        expect(first.start.exitCode).toBe(0);
        const { workerPid } = await liveIdentity(id);
        const oldId = (await readFileContainer(id, CLEANUP_MARKER)).trim();

        // Simulate a process for which both signals fail. The cleanup must
        // retain its record, log the survivor, and allow a new generation.
        const cleanup = await execContainer(id, [
          "bash",
          "-c",
          `kill() { return 1; }; source ${MODULE_DIR}/scripts/pre_install.sh`,
        ]);
        expect(cleanup.exitCode).toBe(0);
        expect(cleanup.stderr).toContain(
          `Previous Cursor worker (pid ${workerPid}) survived SIGKILL.`,
        );
        expect((await readFileContainer(id, CLEANUP_MARKER)).trim()).not.toBe(
          oldId,
        );
        expect(await processAlive(id, workerPid)).toBe(true);
        expect(await workerRecords(id)).toHaveLength(1);
        expect(await exists(id, STATE_FILE)).toBe(false);
        expect(await exists(id, TOKEN_FILE)).toBe(false);

        const start = await execContainer(id, [
          "env",
          ...DISPATCH_ENV,
          "bash",
          "-c",
          scripts.start,
        ]);
        expect(start.exitCode, start.stdout).toBe(0);
        expect(await workerCount(id)).toBe(2);
        expect(await readState(id)).toMatch(/^working \d+$/);
      },
      90 * 1000,
    );

    it("rotates a claimed generation and may run two workers without cleanup", async () => {
      const { id, scripts } = await setup();
      await stubAgent(id, "sleep 120");
      const first = await runDispatched(id, scripts);
      expect(first.start.exitCode).toBe(0);
      const { workerPid: previousPid } = await liveIdentity(id);
      const previousId = (await readFileContainer(id, CLEANUP_MARKER)).trim();
      expect(await exists(id, `${MODULE_DIR}/started/${previousId}`)).toBe(
        true,
      );

      // A valid marker and claim are left behind when cleanup is skipped.
      const repeated = await execContainer(id, [
        "env",
        ...DISPATCH_ENV,
        "bash",
        "-c",
        scripts.start,
      ]);
      expect(repeated.exitCode, repeated.stdout).toBe(0);
      expect(repeated.stdout).toContain("starting a new generation anyway");
      const nextId = (await readFileContainer(id, CLEANUP_MARKER)).trim();
      expect(nextId).not.toBe(previousId);
      expect(await exists(id, `${MODULE_DIR}/started/${nextId}`)).toBe(true);
      expect(await processAlive(id, previousPid)).toBe(true);
      expect(await workerCount(id)).toBe(2);
      expect(await readState(id)).toMatch(/^working \d+$/);
      expect(await readState(id)).not.toBe(`working ${previousPid}`);
    });

    it("runs nothing from a supervisor launched before a newer cleanup", async () => {
      // A supervisor or worker that publishes its record after a newer
      // cleanup has already scanned would run untracked. Each one checks
      // that the marker still holds the id of the cleanup its start step
      // followed, and exits otherwise.
      const { id, scripts } = await setup();
      await stubAgent(id, "sleep 30");
      const first = await runDispatched(id, scripts);
      expect(first.start.exitCode).toBe(0);
      const firstCleanupId = (
        await readFileContainer(id, CLEANUP_MARKER)
      ).trim();
      // A newer agent start's cleanup stops the first run and replaces
      // the marker.
      const cleanup = await execContainer(id, [
        "bash",
        "-c",
        scripts.preInstall,
      ]);
      expect(cleanup.exitCode).toBe(0);
      expect(await workerCount(id)).toBe(0);
      const currentCleanupId = (
        await readFileContainer(id, CLEANUP_MARKER)
      ).trim();
      expect(currentCleanupId).not.toBe(firstCleanupId);

      // The id travels as an argument, never in the script file, so a late
      // start that runs a newer start's script still carries its own id.
      const supervisor = await readFileContainer(
        id,
        `${MODULE_DIR}/scripts/supervise.sh`,
      );
      expect(supervisor).not.toContain(firstCleanupId);
      expect(supervisor).not.toContain(currentCleanupId);
      for (const args of [[firstCleanupId], []]) {
        const stale = await execContainer(id, [
          "env",
          ...DISPATCH_ENV,
          "bash",
          `${MODULE_DIR}/scripts/supervise.sh`,
          ...args,
        ]);
        expect(stale.exitCode, args.join(" ")).not.toBe(0);
        expect(await workerCount(id)).toBe(0);
        expect(await allRecords(id)).toEqual([]);
        expect(await exists(id, STATE_FILE)).toBe(false);
      }
    });

    it("does not touch state or token once a newer cleanup has started", async () => {
      // A supervisor outlives the start that launched it. Once a newer
      // cleanup has replaced the marker, the state file and token belong
      // to the newer run, so the old supervisor must leave them alone even
      // when its worker finishes.
      const { id, scripts } = await setup();
      await stubAgent(id, "sleep 2");
      const first = await runDispatched(id, scripts);
      expect(first.start.exitCode).toBe(0);
      expect(await readState(id)).toMatch(/^working \d+$/);

      // Stand in for a newer cleanup and start: a new id in the marker, the
      // new run's state and token.
      await writeFileContainer(id, CLEANUP_MARKER, "newer-cleanup-id\n", {
        user: "root",
      });
      await writeFileContainer(id, STATE_FILE, "pending\n", { user: "root" });
      await writeFileContainer(id, TOKEN_FILE, "newer-token", {
        user: "root",
      });

      await waitFor(
        async () => (await allRecords(id)).length === 0,
        "the old supervisor to exit",
      );
      expect(await readState(id)).toBe("pending");
      expect(await readFileContainer(id, TOKEN_FILE)).toBe("newer-token");
    });

    it("does not start when record directories are unusable", async () => {
      // A broken record directory prevents the start step from publishing
      // a worker record, although cleanup still publishes a marker.
      const { id, scripts } = await setup();
      await stubAgent(id, "sleep 30");
      const first = await runDispatched(id, scripts);
      expect(first.start.exitCode).toBe(0);
      expect(await exists(id, CLEANUP_MARKER)).toBe(true);
      // Stop the first worker with a successful cleanup, then break the
      // next one.
      const cleanup = await execContainer(id, [
        "bash",
        "-c",
        scripts.preInstall,
      ]);
      expect(cleanup.exitCode).toBe(0);
      await execContainer(id, ["rm", "-rf", SUPERVISORS_DIR]);
      await writeFileContainer(id, SUPERVISORS_DIR, "not a directory\n", {
        user: "root",
      });

      const run = (script: string) =>
        execContainer(id, ["env", ...DISPATCH_ENV, "bash", "-c", script]);
      expect((await run(scripts.preInstall)).exitCode).toBe(0);
      expect(await exists(id, CLEANUP_MARKER)).toBe(true);
      expect((await run(scripts.install)).exitCode).toBe(0);
      const start = await run(scripts.start);
      expect(start.exitCode).toBe(1);
      expect(await workerCount(id)).toBe(0);
      expect(await exists(id, TOKEN_FILE)).toBe(false);
    });

    it("starts a new generation when cleanup leaves no usable marker", async () => {
      for (const marker of [null, "incomplete"]) {
        const { id, scripts } = await setup();
        await stubAgent(id, "sleep 120");
        const first = await runDispatched(id, scripts);
        expect(first.start.exitCode).toBe(0);
        const { supervisorPid: previousSupervisor, workerPid: previousPid } =
          await liveIdentity(id);
        const previousId = (await readFileContainer(id, CLEANUP_MARKER)).trim();

        // Cleanup did not run or stopped before publishing. The old worker
        // still lives; fallback must not signal it or trust any stale pid.
        if (marker === null) {
          await execContainer(id, ["rm", CLEANUP_MARKER]);
        } else {
          await writeFileContainer(id, CLEANUP_MARKER, `${marker}\n`, {
            user: "root",
          });
        }
        const unrelated = await startSleeper(id);
        await writeFileContainer(
          id,
          `${WORKERS_DIR}/${unrelated.pid}.1`,
          `${unrelated.pid} fake-boot 1\n`,
          { user: "root" },
        );
        await writeFileContainer(id, STATE_FILE, "done 3\n", { user: "root" });

        const runStart = () =>
          execContainer(id, [
            "env",
            ...DISPATCH_ENV,
            "bash",
            "-c",
            scripts.start,
          ]);
        const second = await runStart();
        expect(second.exitCode, second.stdout).toBe(0);
        expect(second.stdout).toContain("starting a worker anyway");
        const newId = (await readFileContainer(id, CLEANUP_MARKER)).trim();
        expect(newId).toMatch(/^[0-9a-f-]+$/);
        expect(newId).not.toBe(previousId);
        expect(await processAlive(id, previousPid)).toBe(true);
        expect(await processAlive(id, unrelated.pid)).toBe(true);
        expect(await workerCount(id)).toBe(2);
        expect(await readState(id)).toMatch(/^working \d+$/);
        expect(await readState(id)).not.toBe(`working ${previousPid}`);

        // The old supervisor cannot overwrite new state or remove the new
        // token after the marker has rotated.
        await execContainer(id, ["kill", "-TERM", previousPid]);
        await waitFor(
          async () => !(await processAlive(id, previousPid)),
          "previous worker exit",
        );
        await waitFor(
          async () =>
            !(await supervisorRecords(id)).some((record) =>
              record.startsWith(`${previousSupervisor} `),
            ),
          "previous supervisor exit",
        );
        const newState = await readState(id);
        expect(newState).toMatch(/^working \d+$/);
        expect(await exists(id, TOKEN_FILE)).toBe(true);
      }
    });
  });

  it("clears the previous run's worker, state, token, and records before a start", async () => {
    const { id, scripts } = await setup();
    await stubAgent(id, "sleep 30");
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode).toBe(0);
    const { supervisorPid, workerPid } = await liveIdentity(id);

    const cleanup = await execContainer(id, [
      "env",
      ...DISPATCH_ENV,
      "bash",
      "-c",
      scripts.preInstall,
    ]);
    expect(cleanup.exitCode, cleanup.stderr).toBe(0);
    expect(cleanup.stdout).not.toContain("test-user-token");
    expect(await processAlive(id, supervisorPid)).toBe(false);
    expect(await processAlive(id, workerPid)).toBe(false);
    await waitFor(async () => (await workerCount(id)) === 0, "worker exit");
    // A stopped worker did not finish, so no terminal state is left.
    expect(await exists(id, STATE_FILE)).toBe(false);
    expect(await exists(id, TOKEN_FILE)).toBe(false);
    expect(await allRecords(id)).toEqual([]);
  });

  it("stops a live worker on workspace stop without publishing a marker", async () => {
    const { id, scripts } = await setup();
    await stubAgent(id, "sleep 120");
    const first = await runDispatched(id, scripts);
    expect(first.start.exitCode).toBe(0);
    const { supervisorPid, workerPid } = await liveIdentity(id);

    const stopped = await execContainer(id, ["bash", "-c", scripts.stop]);
    expect(stopped.exitCode, stopped.stdout).toBe(0);
    expect(await processAlive(id, supervisorPid)).toBe(false);
    expect(await processAlive(id, workerPid)).toBe(false);
    expect(await exists(id, STATE_FILE)).toBe(false);
    expect(await exists(id, TOKEN_FILE)).toBe(false);
    expect(await exists(id, CLEANUP_MARKER)).toBe(false);
    expect(await allRecords(id)).toEqual([]);

    // A later start must not inherit the stop's marker or state.
    const next = await runDispatched(id, scripts);
    expect(next.start.exitCode).toBe(0);
    expect(await readState(id)).toMatch(/^working \d+$/);
    expect(await workerCount(id)).toBe(1);
  });

  it("keeps stop best-effort when records cannot be verified", async () => {
    const { id, scripts } = await setup();
    await execContainer(id, ["mkdir", "-p", WORKERS_DIR]);
    await writeFileContainer(id, CLEANUP_MARKER, "old-generation\n", {
      user: "root",
    });
    await writeFileContainer(id, STATE_FILE, "working 1\n", { user: "root" });
    await writeFileContainer(id, TOKEN_FILE, "old-token", { user: "root" });
    const badRecord = `${WORKERS_DIR}/unknown`;
    await writeFileContainer(id, badRecord, "unverifiable\n", { user: "root" });
    const stopped = await execContainer(id, ["bash", "-c", scripts.stop]);
    expect(stopped.exitCode).toBe(0);
    expect(stopped.stderr).toContain("Unverifiable Cursor worker record");
    expect(await exists(id, badRecord)).toBe(true);
    expect(await exists(id, STATE_FILE)).toBe(false);
    expect(await exists(id, TOKEN_FILE)).toBe(false);
    expect(await exists(id, CLEANUP_MARKER)).toBe(false);
    // A failed stop must not block a later start.
    await stubAgent(id, "sleep 120");
    const next = await runDispatched(id, scripts);
    expect(next.start.exitCode).toBe(0);
    expect(await workerCount(id)).toBe(1);
  });

  it("stops the worker on TERM without recording a terminal state", async () => {
    const { id, scripts } = await setup();
    await stubAgent(id, "sleep 30");
    await runDispatched(id, scripts);
    const state = await readState(id);
    expect(state).toMatch(/^working \d+$/);
    const { supervisorPid } = await liveIdentity(id);

    await execContainer(id, ["kill", "-TERM", supervisorPid]);
    await waitFor(
      async () => !(await processAlive(id, supervisorPid)),
      "supervisor exit",
    );
    expect(await workerCount(id)).toBe(0);
    // The supervisor removed its own and the worker's records and the
    // token, and did not report the stop as the worker finishing.
    expect(await allRecords(id)).toEqual([]);
    expect(await exists(id, TOKEN_FILE)).toBe(false);
    expect(await readState(id)).toBe(state);
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
      "scripts/pre_install.sh",
      "scripts/install.sh",
      "scripts/start.sh",
      "logs/pre_install.log",
      "logs/install.log",
      "logs/start.log",
      "logs/worker.log",
      "scripts/supervise.sh",
      "worker-state",
      "cleanup-complete",
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
    // The token reaches the worker as a file, never as an argument or an
    // API key.
    expect(args[args.indexOf("--auth-token-file") + 1]).toBe(TOKEN_FILE);
    expect(args).not.toContain("--auth-token");
    expect(args).not.toContain("test-user-token");
    expect(await readFileContainer(id, TOKEN_FILE)).toBe("test-user-token");
    const mode = await execContainer(id, ["stat", "-c", "%a", TOKEN_FILE]);
    expect(mode.stdout.trim()).toBe("600");
    expect(args).toContain("start");
    expect(args).not.toContain("--computer-use");

    // The supervisor file on disk must reference the variable, never
    // carry the token itself.
    const supervisor = await readFileContainer(
      id,
      `${MODULE_DIR}/scripts/supervise.sh`,
    );
    expect(supervisor).toContain(`--auth-token-file "${TOKEN_FILE}"`);
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
    // The agent's commands run as children of the worker, so the token
    // must not be in its environment either.
    expect(env.stdout).not.toContain("AGENT_RELAY_CURSOR_TOKEN=");
  });

  it("passes the credential as --auth-token-file even with a stale credential kind", async () => {
    // Module 0.2.0 to 0.4.0 exported AGENT_RELAY_CURSOR_CREDENTIAL_KIND
    // and switched to CURSOR_API_KEY on api_key. A leftover value in the
    // environment must not change how the credential reaches the CLI.
    const { id, scripts } = await setup();
    await stubAgent(
      id,
      'printf "%s\\n" "$@" >/tmp/agent-args; printf "%s" "${CURSOR_API_KEY-unset}" >/tmp/agent-api-key; sleep 30',
    );
    const { start } = await runScripts(id, scripts, [
      ...DISPATCH_ENV,
      "AGENT_RELAY_CURSOR_CREDENTIAL_KIND=api_key",
    ]);
    expect(start.exitCode).toBe(0);
    const args = (await readFileContainer(id, "/tmp/agent-args")).split("\n");
    expect(args[args.indexOf("--auth-token-file") + 1]).toBe(TOKEN_FILE);
    expect(await readFileContainer(id, TOKEN_FILE)).toBe("test-user-token");
    expect(await readFileContainer(id, "/tmp/agent-api-key")).toBe("unset");
  });

  it("passes --computer-use when enabled", async () => {
    const { id, scripts } = await setup({ computer_use: "true" });
    await stubAgent(id, 'printf "%s\\n" "$@" >/tmp/agent-args; sleep 30');
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode).toBe(0);
    const args = (await readFileContainer(id, "/tmp/agent-args")).split("\n");
    expect(args).toContain("--computer-use");
  });

  it("passes an explicit desktop share mode so it cannot swallow start", async () => {
    // --share-desktop takes an optional mode; bare, it consumes the
    // next argument and the CLI rejects "start" as a mode.
    const { id, scripts } = await setup({
      computer_use: "true",
      share_desktop: "true",
    });
    await stubAgent(id, 'printf "%s\\n" "$@" >/tmp/agent-args; sleep 30');
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode).toBe(0);
    const args = (await readFileContainer(id, "/tmp/agent-args")).split("\n");
    expect(args).toContain("--share-desktop=view_and_control");
    expect(args).toContain("start");
  });

  it("appends additional_args before start, in order, one argument per element", async () => {
    const { id, scripts } = await setup({
      additional_args: JSON.stringify([
        "--name",
        "two words $HOME",
        "--name",
        `it"s`,
        "--verbose",
      ]),
    });
    await stubAgent(id, 'printf "%s\\n" "$@" >/tmp/agent-args; sleep 30');
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode).toBe(0);
    const args = (await readFileContainer(id, "/tmp/agent-args")).split("\n");
    expect(args[0]).toBe("worker");
    // A flag can repeat, and arguments reach the CLI verbatim and in order:
    // no word splitting or expansion.
    const at = args.indexOf("--name");
    expect(args.slice(at, at + 5)).toEqual([
      "--name",
      "two words $HOME",
      "--name",
      'it"s',
      "--verbose",
    ]);
    // The subcommand stays last, after every flag.
    expect(args.indexOf("start")).toBe(at + 5);
    expect(args[args.indexOf("--pool") + 1]).toBe(POOL_NAME);
  });

  it("records the exit code when the worker exits", async () => {
    const { id, scripts } = await setup();
    await stubAgent(id, "exit 3");
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode).toBe(0);
    expect(await waitForState(id, /^done \d+$/)).toBe("done 3");
    // The claim is over, so the supervisor removes the token.
    const token = await execContainer(id, ["test", "-e", TOKEN_FILE]);
    expect(token.exitCode).not.toBe(0);
    // A supervisor whose worker exits on its own removes both records.
    await waitFor(
      async () => (await allRecords(id)).length === 0,
      "identity record removal",
    );
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

  describe("session_attached_metadata_script", () => {
    // Stands in for the worker's management server. The body comes from a
    // file the test writes; a missing file is a failed scrape, and any
    // other URL is a wiring bug.
    const stubMetrics = (id: string, url: string) =>
      stubBinary(
        id,
        "/usr/local/bin/curl",
        [
          `case "$*" in *"${url}/metrics"*) ;; *) echo "unexpected curl $*" >&2; exit 7 ;; esac`,
          "[ -f /tmp/metrics ] || exit 22",
          "cat /tmp/metrics",
        ].join("\n"),
      );

    const metrics = (active: string) =>
      [
        "# HELP cursor_self_hosted_worker_session_active 1 when a session is running.",
        "# TYPE cursor_self_hosted_worker_session_active gauge",
        `cursor_self_hosted_worker_session_active ${active}`,
        'cursor_self_hosted_worker_session_ends_total{reason="idle_release"} 3',
        "cursor_self_hosted_worker_connected 1",
        "",
      ].join("\n");

    const sample = async (id: string, script: string, body?: string) => {
      if (body === undefined) {
        await execContainer(id, ["rm", "-f", "/tmp/metrics"]);
      } else {
        await writeFileContainer(id, "/tmp/metrics", body, { user: "root" });
      }
      return execContainer(id, ["bash", "-c", script]);
    };

    const workerArgs = async (id: string) =>
      (await readFileContainer(id, "/tmp/agent-args")).split("\n");

    it("reads the session gauge from the live worker's management server", async () => {
      const { id, scripts, attachedScript } = await setup({
        management_addr: ":3290",
      });
      await stubAgent(id, 'printf "%s\\n" "$@" >/tmp/agent-args; sleep 30');
      // A wildcard bind is read over loopback.
      await stubMetrics(id, "http://127.0.0.1:3290");
      await runDispatched(id, scripts);
      const args = await workerArgs(id);
      expect(args[args.indexOf("--management-addr") + 1]).toBe(":3290");
      // The flag must come before the start subcommand.
      expect(args.indexOf("--management-addr")).toBeLessThan(
        args.indexOf("start"),
      );

      const held = await sample(id, attachedScript, metrics("1"));
      expect(held.exitCode, held.stderr).toBe(0);
      expect(held.stdout.trim()).toBe("attached");

      const free = await sample(id, attachedScript, metrics("0"));
      expect(free.exitCode, free.stderr).toBe(0);
      expect(free.stdout.trim()).toBe("unattached");

      // Unknown is an error sample, never false, so the relay can tell a
      // broken probe from an ended session.
      const unreachable = await sample(id, attachedScript);
      expect(unreachable.exitCode).not.toBe(0);
      expect(unreachable.stdout.trim()).toBe("");

      const missing = await sample(
        id,
        attachedScript,
        "cursor_self_hosted_worker_connected 1\n",
      );
      expect(missing.exitCode).not.toBe(0);
      expect(missing.stdout.trim()).toBe("");
    });

    it("binds loopback by default", async () => {
      const { id, scripts, attachedScript } = await setup();
      await stubAgent(id, 'printf "%s\\n" "$@" >/tmp/agent-args; sleep 30');
      await stubMetrics(id, "http://127.0.0.1:3287");
      await runDispatched(id, scripts);
      const args = await workerArgs(id);
      expect(args[args.indexOf("--management-addr") + 1]).toBe(
        "127.0.0.1:3287",
      );
      const held = await sample(id, attachedScript, metrics("1"));
      expect(held.exitCode, held.stderr).toBe(0);
      expect(held.stdout.trim()).toBe("attached");
    });

    it("reports stopped once the worker exits", async () => {
      const { id, scripts, attachedScript } = await setup();
      await stubAgent(id, "exit 0");
      await stubMetrics(id, "http://127.0.0.1:3287");
      await runDispatched(id, scripts);
      await waitForState(id, /^done \d+$/);
      const result = await sample(id, attachedScript, metrics("1"));
      expect(result.exitCode, result.stderr).toBe(0);
      expect(result.stdout.trim()).toBe("stopped");
    });

    it("reports stopped without a live worker", async () => {
      const { id, attachedScript } = await setup({ install_cli: "false" });
      await stubMetrics(id, "http://127.0.0.1:3287");
      await execContainer(id, ["mkdir", "-p", MODULE_DIR]);
      // The server would claim a session; with no live worker it is never
      // consulted. "working 1" is a live pid that is not the CLI, as after
      // pid reuse.
      for (const state of [
        undefined,
        "idle",
        "done 0",
        "failed runner-agent-missing",
        "working 999999",
        "working 1",
      ]) {
        if (state === undefined) {
          await execContainer(id, ["rm", "-f", STATE_FILE]);
        } else {
          await writeFileContainer(id, STATE_FILE, `${state}\n`, {
            user: "root",
          });
        }
        const result = await sample(id, attachedScript, metrics("1"));
        expect(result.exitCode, `${state}: ${result.stderr}`).toBe(0);
        expect(result.stdout.trim(), String(state)).toBe("stopped");
      }
    });

    it("reports disabled when management_addr is empty", async () => {
      const { id, scripts, attachedScript } = await setup({
        management_addr: "",
      });
      await stubAgent(id, 'printf "%s\\n" "$@" >/tmp/agent-args; sleep 30');
      await stubBinary(id, "/usr/local/bin/curl", "exit 99");
      await runDispatched(id, scripts);
      expect(await workerArgs(id)).not.toContain("--management-addr");
      const result = await execContainer(id, ["bash", "-c", attachedScript]);
      expect(result.exitCode, result.stderr).toBe(0);
      expect(result.stdout.trim()).toBe("disabled");
    });
  });
});
