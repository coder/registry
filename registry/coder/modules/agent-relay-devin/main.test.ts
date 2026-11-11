import {
  afterAll,
  afterEach,
  beforeAll,
  beforeEach,
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
// throwaway container. A Bun.serve fake of Devin's static host serves a
// stub devin-remote, its .sha256, and latest_linux_<arch>, so download,
// verification, and the supervisor lifecycle the relay's reaper depends
// on (idle, working, serving, done, failed) are observed rather than
// grepped for. The real devin-remote and Devin's gateway are out of
// scope. `coder` is stubbed so the `coder exp sync` ordering calls
// succeed without a control plane.

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
const MODULE_DIR = "/root/.coder-modules/coder/agent-relay-devin";
const STATE_FILE = `${MODULE_DIR}/remote-state`;
// Where unreleased builds of the module staged the token, under $HOME.
const LEGACY_TOKEN_FILE = `${MODULE_DIR}/remote-token`;
// Each start stages the token in its own runtime directory, here under
// /tmp because the container has no XDG_RUNTIME_DIR. Root's uid is 0.
const RUNTIME_GLOB = "/tmp/agent-relay-devin-0.*";
const LOG_FILE = `${MODULE_DIR}/logs/remote.log`;
const SUPERVISORS_DIR = `${MODULE_DIR}/supervisors`;
const REMOTES_DIR = `${MODULE_DIR}/remotes`;
const CLEANUP_MARKER = `${MODULE_DIR}/cleanup-complete`;
const CACHE_DIR = "/root/.devin/worker/cache";
const WORKDIR = "/root/devin";
const STATE_DIR = "/root/.devin/worker/sessions";
// The container's `uname -m`, mapped as the install step maps it.
const ARCH = process.arch === "arm64" ? "arm64" : "x64";
const SHA = "0a1b2c3d4e";
const SESSION_ID = "devin-0123456789abcdef";
const TOKEN = "test-connect-token";
// The gateway URL carries shell metacharacters to prove parameter values
// reach the remote as data rather than being parsed as code.
const GATEWAY_URL = "wss://gateway.example/outpost?x=$(touch /tmp/injected)";
const DISPATCH_ENV = [
  `AGENT_RELAY_DEVIN_TOKEN=${TOKEN}`,
  `AGENT_RELAY_SESSION_ID=${SESSION_ID}`,
  `AGENT_RELAY_DEVIN_GATEWAY_URL=${GATEWAY_URL}`,
  `AGENT_RELAY_DEVIN_REMOTE_BINARY_SHA=${SHA}`,
  "AGENT_RELAY_DEVIN_SESSION_KIND=new",
];
const ALLOWED_ENV = [
  "PATH",
  "HOME",
  "USER",
  "LOGNAME",
  "TMPDIR",
  "LANG",
  "TZ",
  "DISPLAY",
  "WAYLAND_DISPLAY",
  "XAUTHORITY",
];
const binaryName = (sha = SHA) => `devin-remote_${sha}_linux_${ARCH}`;
const cachedBinary = (sha = SHA) => `${CACHE_DIR}/${binaryName(sha)}`;

// Stands in for devin-remote. It records each run, then sources
// /tmp/remote-behavior when a test wrote one (to log, exit, or ignore
// TERM), then idles. It must not exec, so its command line keeps the
// cached binary's name the status scripts look for.
const STUB_REMOTE = [
  "#!/usr/bin/env bash",
  'printf "%s\\n" "$$" >>/tmp/remote-runs',
  "[ ! -f /tmp/remote-behavior ] || . /tmp/remote-behavior",
  "sleep 120",
  "",
].join("\n");
const sha256Hex = (body: string) =>
  new Bun.CryptoHasher("sha256").update(body).digest("hex");

// The log line devin-remote prints once it reaches the gateway, coloured
// the way tracing colours it: the field name and "=" are wrapped in
// escape sequences, so the raw text does not contain the pattern.
const CONNECTED_LINE =
  "\\033[2m2026-11-11T00:00:00.000000Z\\033[0m \\033[32m INFO\\033[0m \\033[2mdevin_remote::outpost\\033[0m\\033[2m:\\033[0m connected to outpost gateway \\033[3mendpoint\\033[0m\\033[2m=\\033[0mwss://gateway.example/outpost";

type Route = { status: number; body: string };
let routes: Record<string, Route> = {};
let requests: string[] = [];
let server: ReturnType<typeof Bun.serve>;
let baseUrl = "";

// The happy path: latest points at SHA, and the binary matches its hash.
const serveRelease = (sha = SHA, body = STUB_REMOTE) => {
  routes[`/latest_linux_${ARCH}`] = { status: 200, body: `${sha}\n` };
  routes[`/${binaryName(sha)}`] = { status: 200, body };
  routes[`/${binaryName(sha)}.sha256`] = {
    status: 200,
    body: `${sha256Hex(body)}\n`,
  };
};
const requestCount = (path: string) =>
  requests.filter((r) => r === path).length;

const setup = async (vars: Record<string, string> = {}) => {
  const state = await runTerraformApply(import.meta.dir, {
    agent_id: "foo",
    static_base_url: baseUrl,
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
        attrs.display_name === "Devin remote: Stop Script",
      );
    }
  }
  const scripts = {
    preInstall: byDisplayName["Devin remote: Pre-Install Script"],
    install: byDisplayName["Devin remote: Install Script"],
    start: byDisplayName["Devin remote: Start Script"],
    stop: byDisplayName["Devin remote: Stop Script"],
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

// Shell the stub sources after it records its run.
const remoteBehavior = (id: string, body: string) =>
  writeFileContainer(id, "/tmp/remote-behavior", `${body}\n`, {
    user: "root",
  });

// Runs the pre-install, install, and start steps, as coder-utils orders
// them on the agent, and returns their results.
const runScripts = async (id: string, scripts: Scripts, env: string[]) => {
  const run = (script: string) =>
    execContainer(id, ["env", ...env, "bash", "-c", script]);
  const preInstall = await run(scripts.preInstall);
  expect(preInstall.exitCode, preInstall.stdout).toBe(0);
  const install = await run(scripts.install);
  // The install step never fails the build.
  expect(install.exitCode, install.stdout).toBe(0);
  const start = await run(scripts.start);
  return { preInstall, install, start };
};

const runDispatched = (id: string, scripts: Scripts, extraEnv: string[] = []) =>
  runScripts(id, scripts, [...DISPATCH_ENV, ...extraEnv]);

const readState = async (id: string) =>
  (await readFileContainer(id, STATE_FILE)).trim();

const exists = async (id: string, path: string) =>
  (await execContainer(id, ["test", "-e", path])).exitCode === 0;

// The runtime directories a start staged its token in and has not removed.
const runtimeDirs = async (id: string, glob = RUNTIME_GLOB) => {
  const out = await execContainer(id, [
    "sh",
    "-c",
    `for d in ${glob}; do [ -e "$d" ] && echo "$d"; done; true`,
  ]);
  return out.stdout.split("\n").filter((l) => l !== "");
};

// Every process whose /proc environ holds value, as [pid, ppid] pairs.
const processesHolding = async (id: string, value: string) => {
  const out = await execContainer(id, [
    "bash",
    "-c",
    'v=$1; for p in /proc/[0-9]*; do grep -qaF -- "$v" "$p/environ" 2>/dev/null || continue; s=$(cat "$p/stat" 2>/dev/null) || continue; s=${s##*) }; set -- $s; echo "${p#/proc/} $2"; done',
    "bash",
    value,
  ]);
  return out.stdout
    .split("\n")
    .filter((l) => l !== "")
    .map((l) => l.split(" "));
};

const statusOf = async (id: string, script: string) => {
  const result = await execContainer(id, ["bash", "-c", script]);
  expect(result.exitCode, result.stderr).toBe(0);
  return result.stdout.trim();
};

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
const allRecords = async (id: string) => [
  ...(await recordsIn(id, SUPERVISORS_DIR)),
  ...(await recordsIn(id, REMOTES_DIR)),
];

// The pids of the one live supervisor and remote.
const liveIdentity = async (id: string) => {
  const [supervisor] = await recordsIn(id, SUPERVISORS_DIR);
  const [remote] = await recordsIn(id, REMOTES_DIR);
  return {
    supervisorPid: supervisor.split(" ")[0],
    remotePid: remote.split(" ")[0],
  };
};

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

// Live processes whose argv is the stub serving. pgrep -f would match the
// counting shell itself, so read /proc.
const remoteCount = async (id: string) => {
  const out = await execContainer(id, [
    "sh",
    "-c",
    'n=0; for p in /proc/[0-9]*; do a=$(tr "\\0" " " <"$p/cmdline" 2>/dev/null); case "$a" in "bash "*/devin-remote*" serve "*) s=$(cat "$p/stat" 2>/dev/null); s=${s##*) }; [ "${s%% *}" = Z ] || n=$((n+1));; esac; done; echo $n',
  ]);
  return Number(out.stdout.trim());
};

const remoteRuns = async (id: string) =>
  (await exists(id, "/tmp/remote-runs"))
    ? (await readFileContainer(id, "/tmp/remote-runs"))
        .split("\n")
        .filter((l) => l !== "").length
    : 0;

// The remote's environment, from /proc, as a map.
const environOf = async (id: string, pid: string) => {
  const out = await execContainer(id, [
    "sh",
    "-c",
    `tr '\\0' '\\n' </proc/${pid}/environ`,
  ]);
  expect(out.exitCode, out.stderr).toBe(0);
  const env: Record<string, string> = {};
  for (const line of out.stdout.split("\n")) {
    if (line === "") continue;
    const at = line.indexOf("=");
    env[line.slice(0, at)] = line.slice(at + 1);
  }
  return env;
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

// The supervisor writes terminal state after the remote exits; poll rather
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

const workingPid = async (id: string) => {
  const state = await readState(id);
  expect(state).toMatch(/^working \d+$/);
  return state.split(" ")[1];
};

setDefaultTimeout(60 * 1000);

describe("agent-relay-devin", () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
    server = Bun.serve({
      port: 0,
      fetch(req) {
        const path = new URL(req.url).pathname;
        requests.push(path);
        const route = routes[path];
        if (!route) return new Response("not found", { status: 404 });
        return new Response(route.body, { status: route.status });
      },
    });
    baseUrl = `http://localhost:${server.port}`;
  });

  afterAll(() => {
    server?.stop(true);
  });

  beforeEach(() => {
    routes = {};
    requests = [];
    serveRelease();
  });

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("sets no coder_env for the connect token's variable", async () => {
    // The agent injects AGENT_RELAY_DEVIN_TOKEN from the workspace secret.
    // A coder_env of that name would put the token in Terraform state.
    const state = await runTerraformApply(import.meta.dir, { agent_id: "foo" });
    const envNames = state.resources
      .filter((resource) => resource.type === "coder_env")
      .flatMap((resource) =>
        resource.instances.map((instance) => instance.attributes.name),
      );
    expect(envNames).toContain("AGENT_RELAY_SESSION_ID");
    expect(envNames).not.toContain("AGENT_RELAY_DEVIN_TOKEN");
  });

  it("idles without a token, even after a terminal state, and downloads nothing", async () => {
    const { id, scripts, statusScript, attachedScript } = await setup();
    await execContainer(id, ["mkdir", "-p", MODULE_DIR]);
    await writeFileContainer(id, STATE_FILE, "done 3\n", { user: "root" });
    await writeFileContainer(id, LEGACY_TOKEN_FILE, "stale-token", {
      user: "root",
    });
    // A runtime directory a killed run left behind.
    await execContainer(id, [
      "sh",
      "-c",
      "mkdir -m 700 /tmp/agent-relay-devin-0.stale && printf stale-token >/tmp/agent-relay-devin-0.stale/token",
    ]);
    // No AGENT_RELAY_DEVIN_TOKEN: a workspace a human created by hand, or
    // a restart after the ephemeral secret was cleared.
    const { install, start } = await runScripts(
      id,
      scripts,
      DISPATCH_ENV.slice(1),
    );
    expect(install.stdout).toContain("skipping the devin-remote download");
    expect(start.exitCode).toBe(0);
    expect(start.stdout).toContain("No Devin connect token in this build");
    expect(await readState(id)).toBe("idle");
    expect(await statusOf(id, statusScript)).toBe("idle");
    expect(await statusOf(id, attachedScript)).toBe("stopped");
    expect(await runtimeDirs(id)).toEqual([]);
    expect(await exists(id, LEGACY_TOKEN_FILE)).toBe(false);
    expect(requests).toEqual([]);
    expect(await remoteRuns(id)).toBe(0);

    // Without the pre-install cleanup, the start step itself removes a
    // stale runtime directory before it idles.
    await execContainer(id, [
      "sh",
      "-c",
      "mkdir -m 700 /tmp/agent-relay-devin-0.stale && printf stale-token >/tmp/agent-relay-devin-0.stale/token",
    ]);
    const idle = await execContainer(id, ["bash", "-c", scripts.start]);
    expect(idle.exitCode).toBe(0);
    expect(await runtimeDirs(id)).toEqual([]);
    expect(await readState(id)).toBe("idle");
  });

  it("starts the remote from workdir with a clean environment", async () => {
    const { id, scripts, statusScript, attachedScript } = await setup();
    const { install, start } = await runDispatched(id, scripts, [
      "CODER_AGENT_TOKEN=agent-secret",
      "CODER_AGENT_URL=https://coder.example",
      "GIT_ASKPASS=/tmp/coder-askpass",
      "UNRELATED_VARIABLE=should-not-leak",
      "BASH_FUNC_leaky%%=() {  echo leaked; }",
      "LANG=C.UTF-8",
      "DISPLAY=:1",
    ]);
    expect(install.stdout).toContain(`Using devin-remote ${SHA}`);
    expect(start.exitCode, start.stdout).toBe(0);
    expect(start.stdout).toContain("Starting Devin remote (detached)...");
    const pid = await workingPid(id);
    await waitFor(async () => (await remoteRuns(id)) === 1, "the stub to run");

    const env = await environOf(id, pid);
    const names = Object.keys(env).sort();
    for (const name of names) {
      expect(
        ALLOWED_ENV.includes(name) || name.startsWith("DEVIN_"),
        `${name} must not reach the remote`,
      ).toBe(true);
    }
    expect(names.filter((n) => n.startsWith("DEVIN_")).sort()).toEqual([
      "DEVIN_OUTPOST_CONNECT_TOKEN",
      "DEVIN_OUTPOST_GATEWAY_URL",
      "DEVIN_OUTPOST_SESSION_ID",
      "DEVIN_REMOTE_STATE_DIR",
    ]);
    expect(env.DEVIN_OUTPOST_CONNECT_TOKEN).toBe(TOKEN);
    expect(env.DEVIN_OUTPOST_GATEWAY_URL).toBe(GATEWAY_URL);
    expect(env.DEVIN_OUTPOST_SESSION_ID).toBe(SESSION_ID);
    expect(env.DEVIN_REMOTE_STATE_DIR).toBe(`${STATE_DIR}/${SESSION_ID}`);
    expect(env.HOME).toBe("/root");
    expect(env.PATH).toBeTruthy();
    expect(env.LANG).toBe("C.UTF-8");
    expect(env.DISPLAY).toBe(":1");
    for (const name of [
      "CODER_AGENT_TOKEN",
      "CODER_AGENT_URL",
      "AGENT_RELAY_DEVIN_TOKEN",
      "AGENT_RELAY_SESSION_ID",
      "GIT_ASKPASS",
      "UNRELATED_VARIABLE",
      "BASH_FUNC_leaky%%",
    ]) {
      expect(env[name], name).toBeUndefined();
    }
    // The metacharacters in the gateway URL must not have executed.
    expect(await exists(id, "/tmp/injected")).toBe(false);

    const cwd = await execContainer(id, ["readlink", `/proc/${pid}/cwd`]);
    expect(cwd.stdout.trim()).toBe(WORKDIR);
    expect(await exists(id, `${STATE_DIR}/${SESSION_ID}`)).toBe(true);
    const cmdline = await execContainer(id, [
      "sh",
      "-c",
      `tr '\\0' ' ' </proc/${pid}/cmdline`,
    ]);
    expect(cmdline.stdout).toBe(`bash ${cachedBinary()} serve `);

    // The token never reaches the supervisor's file, a command line, a
    // log, the state file, or anything under $HOME.
    const supervisor = await readFileContainer(
      id,
      `${MODULE_DIR}/scripts/supervise.sh`,
    );
    expect(supervisor).not.toContain(TOKEN);
    expect(supervisor).not.toContain(SESSION_ID);
    expect(supervisor).not.toContain(SHA);
    expect(supervisor).toContain('session_id="$AGENT_RELAY_SESSION_ID"');
    const leaked = await execContainer(id, [
      "sh",
      "-c",
      `for p in /proc/[0-9]*; do tr '\\0' ' ' <"$p/cmdline" 2>/dev/null; echo; done; cat ${MODULE_DIR}/logs/*.log ${STATE_FILE}`,
    ]);
    expect(leaked.stdout).not.toContain(TOKEN);
    const onDisk = await execContainer(id, ["grep", "-rlF", TOKEN, "/root"]);
    expect(onDisk.stdout).toBe("");
    expect(onDisk.exitCode).toBe(1);

    // Only the remote's environ, and its children's, holds the token. The
    // supervisor and the watchdog were started without it.
    const { supervisorPid } = await liveIdentity(id);
    const holders = await processesHolding(id, TOKEN);
    expect(holders.map(([p]) => p)).toContain(pid);
    expect(holders.map(([p]) => p)).not.toContain(supervisorPid);
    for (const [holder, parent] of holders) {
      expect(holder === pid || parent === pid, `pid ${holder}`).toBe(true);
    }

    // The remote deleted the staged token once it had read it. The runtime
    // directory stays, empty, until the supervisor exits.
    const [runDir] = await runtimeDirs(id);
    expect(runDir).toBeTruthy();
    const listing = await execContainer(id, ["ls", "-A", runDir]);
    expect(listing.stdout.trim()).toBe("");

    expect(await statusOf(id, statusScript)).toBe("working");
    expect(await statusOf(id, attachedScript)).toBe("attached");
  });

  it("stages the token owner-only under XDG_RUNTIME_DIR and removes it", async () => {
    const { id, scripts } = await setup();
    await execContainer(id, ["mkdir", "-m", "700", "-p", "/tmp/xdg-run"]);
    // Records the modes of the runtime directory and the token at the
    // moment the remote reads it.
    await stubBinary(
      id,
      "/usr/local/bin/cat",
      [
        'for a in "$@"; do last=$a; done',
        'case "${last:-}" in */agent-relay-devin-0.*/token) stat -c "%n %a" "${last%/token}" "$last" >/tmp/token-modes ;; esac',
        'exec /bin/cat "$@"',
      ].join("\n"),
    );
    const { start } = await runDispatched(id, scripts, [
      "XDG_RUNTIME_DIR=/tmp/xdg-run",
    ]);
    expect(start.exitCode, start.stdout).toBe(0);
    const pid = await workingPid(id);
    await waitFor(
      async () => exists(id, "/tmp/token-modes"),
      "the remote to read the token",
    );
    const modes = (await readFileContainer(id, "/tmp/token-modes"))
      .trim()
      .split("\n");
    expect(modes).toHaveLength(2);
    expect(modes[0]).toMatch(/^\/tmp\/xdg-run\/agent-relay-devin-0\.\S+ 700$/);
    expect(modes[1]).toMatch(/\/token 600$/);
    expect(await runtimeDirs(id)).toEqual([]);
    const [runDir] = await runtimeDirs(
      id,
      "/tmp/xdg-run/agent-relay-devin-0.*",
    );
    expect(await exists(id, `${runDir}/token`)).toBe(false);
    expect((await environOf(id, pid)).XDG_RUNTIME_DIR).toBeUndefined();

    // The supervisor removes the directory when the remote is gone.
    const stopped = await execContainer(id, ["bash", "-c", scripts.stop]);
    expect(stopped.exitCode).toBe(0);
    expect(await runtimeDirs(id, "/tmp/xdg-run/agent-relay-devin-0.*")).toEqual(
      [],
    );
  });

  it("drops environment entries bash cannot name before the remote runs", async () => {
    const { id, scripts } = await setup();
    const { start } = await runDispatched(id, scripts, [
      "bad-name=x",
      "1X=y",
      "BASH_FUNC_old()=() { echo leaked; }",
    ]);
    expect(start.exitCode, start.stdout).toBe(0);
    const pid = await workingPid(id);
    await waitFor(async () => (await remoteRuns(id)) === 1, "the stub to run");
    // They did reach the supervisor, which is what makes this case matter.
    const { supervisorPid } = await liveIdentity(id);
    expect(Object.keys(await environOf(id, supervisorPid))).toContain(
      "bad-name",
    );
    const env = await environOf(id, pid);
    for (const name of ["bad-name", "1X", "BASH_FUNC_old()"]) {
      expect(env[name], name).toBeUndefined();
    }
    for (const name of Object.keys(env)) {
      expect(
        ALLOWED_ENV.includes(name) || name.startsWith("DEVIN_"),
        `${name} must not reach the remote`,
      ).toBe(true);
    }
    expect(await readFileContainer(id, LOG_FILE)).toContain(
      "Dropping 3 environment entries bash cannot clear.",
    );
    // Names only on argv: env(1) replaced itself with the remote.
    const cmdline = await execContainer(id, [
      "sh",
      "-c",
      `tr '\\0' ' ' </proc/${pid}/cmdline`,
    ]);
    expect(cmdline.stdout).toBe(`bash ${cachedBinary()} serve `);
  });

  it("reports failed launch and runs nothing when bash has no compgen", async () => {
    const { id, scripts, statusScript } = await setup();
    // BASH_ENV runs in every non-interactive bash, the supervisor included.
    await writeFileContainer(id, "/tmp/no-compgen.sh", "enable -n compgen\n", {
      user: "root",
    });
    const { start } = await runDispatched(id, scripts, [
      "BASH_ENV=/tmp/no-compgen.sh",
      "CODER_AGENT_TOKEN=agent-secret",
    ]);
    expect(start.exitCode).toBe(0);
    expect(await waitForState(id, /^(failed|done) /)).toBe("failed launch");
    expect(await statusOf(id, statusScript)).toBe("failed launch");
    expect(await remoteRuns(id)).toBe(0);
    expect(await readFileContainer(id, LOG_FILE)).toContain(
      "this bash has no compgen builtin",
    );
    await waitFor(
      async () => (await allRecords(id)).length === 0,
      "the supervisor to exit",
    );
    expect(await runtimeDirs(id)).toEqual([]);
    expect(await processesHolding(id, "agent-secret")).toEqual([]);
  });

  it("passes chrome_path and desktop to the remote when set", async () => {
    const { id, scripts } = await setup({
      chrome_path: "/usr/bin/chromium",
      desktop: "true",
    });
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode, start.stdout).toBe(0);
    const pid = await workingPid(id);
    await waitFor(async () => (await remoteRuns(id)) === 1, "the stub to run");
    const env = await environOf(id, pid);
    expect(env.DEVIN_CHROME_PATH).toBe("/usr/bin/chromium");
    expect(env.DEVIN_OUTPOST_DESKTOP).toBe("true");
  });

  it("verifies a pinned SHA once and reuses the cached binary on a rebuild", async () => {
    const { id, scripts } = await setup();
    const first = await runDispatched(id, scripts);
    expect(first.start.exitCode, first.start.stdout).toBe(0);
    expect(first.install.stdout).toContain(`Verified and cached`);
    const firstPid = await workingPid(id);
    expect(requestCount(`/${binaryName()}`)).toBe(1);
    expect(requestCount(`/${binaryName()}.sha256`)).toBe(1);
    // A pinned SHA never consults latest.
    expect(requestCount(`/latest_linux_${ARCH}`)).toBe(0);
    expect(
      (await readFileContainer(id, `${cachedBinary()}.sha256`)).trim(),
    ).toBe(sha256Hex(STUB_REMOTE));
    const mode = await execContainer(id, ["stat", "-c", "%a", cachedBinary()]);
    expect(mode.stdout.trim()).toBe("755");
    // No temp files are left behind in the cache.
    const listing = await execContainer(id, ["ls", "-A", CACHE_DIR]);
    expect(listing.stdout.trim().split("\n").sort()).toEqual([
      binaryName(),
      `${binaryName()}.sha256`,
    ]);

    // A rebuild runs every step again. The cache is hit, and the previous
    // remote is stopped before the new one starts.
    const second = await runDispatched(id, scripts);
    expect(second.install.stdout).toContain("Using the cached, verified");
    expect(second.preInstall.stdout).toContain(
      `Stopping previous Devin remote (pid ${firstPid})`,
    );
    expect(second.start.exitCode, second.start.stdout).toBe(0);
    expect(requestCount(`/${binaryName()}`)).toBe(1);
    expect(await processAlive(id, firstPid)).toBe(false);
    const secondPid = await workingPid(id);
    expect(secondPid).not.toBe(firstPid);
    expect(await remoteCount(id)).toBe(1);
    expect(await allRecords(id)).toHaveLength(2);
  });

  it("resolves latest when the SHA parameter is empty", async () => {
    const latest = "fedcba9876";
    serveRelease(latest);
    const { id, scripts } = await setup();
    const { install, start } = await runScripts(id, scripts, [
      ...DISPATCH_ENV.filter(
        (e) => !e.startsWith("AGENT_RELAY_DEVIN_REMOTE_BINARY_SHA="),
      ),
      "AGENT_RELAY_DEVIN_REMOTE_BINARY_SHA=",
    ]);
    expect(install.stdout).toContain(
      `Using the latest devin-remote, ${latest}.`,
    );
    expect(start.exitCode, start.stdout).toBe(0);
    expect(requestCount(`/latest_linux_${ARCH}`)).toBe(1);
    expect(requestCount(`/${binaryName(latest)}`)).toBe(1);
    expect(requestCount(`/${binaryName()}`)).toBe(0);
    await workingPid(id);
    expect(await exists(id, cachedBinary(latest))).toBe(true);
  });

  it("reports failed checksum and never runs a binary that does not match", async () => {
    routes[`/${binaryName()}.sha256`] = {
      status: 200,
      body: `${"0".repeat(64)}\n`,
    };
    const { id, scripts, statusScript } = await setup();
    const { install, start } = await runDispatched(id, scripts);
    expect(install.stdout).toContain("does not match its published SHA-256");
    expect(start.exitCode).toBe(1);
    expect(await readState(id)).toBe("failed checksum");
    expect(await statusOf(id, statusScript)).toBe("failed checksum");
    expect(await exists(id, cachedBinary())).toBe(false);
    expect(await runtimeDirs(id)).toEqual([]);
    expect(await remoteRuns(id)).toBe(0);
  });

  it("reports failed checksum when the published hash is malformed", async () => {
    routes[`/${binaryName()}.sha256`] = { status: 200, body: "not-a-hash\n" };
    const { id, scripts } = await setup();
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode).toBe(1);
    expect(await readState(id)).toBe("failed checksum");
    expect(await remoteRuns(id)).toBe(0);
  });

  it("reports failed download when the binary is not published", async () => {
    delete routes[`/${binaryName()}`];
    const { id, scripts, statusScript } = await setup();
    const { install, start } = await runDispatched(id, scripts);
    expect(install.stdout).toContain(
      `Cannot download devin-remote ${SHA} for linux ${ARCH}`,
    );
    expect(start.exitCode).toBe(1);
    expect(await readState(id)).toBe("failed download");
    expect(await statusOf(id, statusScript)).toBe("failed download");
    expect(await remoteRuns(id)).toBe(0);
    const listing = await execContainer(id, ["ls", "-A", CACHE_DIR]);
    expect(listing.stdout.trim()).toBe("");
  });

  it("reports failed download for a SHA that is not a commit hash", async () => {
    const { id, scripts } = await setup();
    const { start } = await runScripts(id, scripts, [
      ...DISPATCH_ENV.filter(
        (e) => !e.startsWith("AGENT_RELAY_DEVIN_REMOTE_BINARY_SHA="),
      ),
      "AGENT_RELAY_DEVIN_REMOTE_BINARY_SHA=../../etc",
    ]);
    expect(start.exitCode).toBe(1);
    expect(await readState(id)).toBe("failed download");
    expect(requests).toEqual([]);
  });

  it("runs a baked remote_binary without downloading", async () => {
    const { id, scripts, statusScript } = await setup({
      install_remote: "false",
      remote_binary: "/opt/devin/devin-remote",
    });
    await execContainer(id, ["mkdir", "-p", "/opt/devin"]);
    await stubBinary(id, "/opt/devin/devin-remote", STUB_REMOTE);
    const { install, start } = await runDispatched(id, scripts);
    expect(install.stdout).toContain("remote_binary is set");
    expect(start.exitCode, start.stdout).toBe(0);
    const pid = await workingPid(id);
    const cmdline = await execContainer(id, [
      "sh",
      "-c",
      `tr '\\0' ' ' </proc/${pid}/cmdline`,
    ]);
    expect(cmdline.stdout).toBe("bash /opt/devin/devin-remote serve ");
    expect(await statusOf(id, statusScript)).toBe("working");
    expect(requests).toEqual([]);
  });

  it("reports failed remote-binary-missing when the baked binary is absent", async () => {
    const { id, scripts } = await setup({
      install_remote: "false",
      remote_binary: "/opt/devin/devin-remote",
    });
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode).toBe(1);
    expect(await readState(id)).toBe("failed remote-binary-missing");
    expect(await runtimeDirs(id)).toEqual([]);
  });

  it("reports failed invalid-session for an unsafe session id or no gateway", async () => {
    const { id, scripts } = await setup();
    for (const env of [
      ["AGENT_RELAY_SESSION_ID=../escape"],
      ["AGENT_RELAY_SESSION_ID=.."],
      ["AGENT_RELAY_SESSION_ID="],
      ["AGENT_RELAY_DEVIN_GATEWAY_URL="],
    ]) {
      const { start } = await runDispatched(id, scripts, env);
      expect(start.exitCode, env[0]).toBe(1);
      expect(await readState(id), env[0]).toBe("failed invalid-session");
      expect(await runtimeDirs(id)).toEqual([]);
    }
    expect(await exists(id, "/root/.devin/worker/escape")).toBe(false);
    expect(await remoteRuns(id)).toBe(0);
  });

  it("warns on resume when Devin's stamps are missing, and still starts", async () => {
    const { id, scripts } = await setup();
    const resume = ["AGENT_RELAY_DEVIN_SESSION_KIND=resume"];
    const missing = await runDispatched(id, scripts, resume);
    expect(missing.start.exitCode, missing.start.stdout).toBe(0);
    expect(missing.start.stdout).toContain(
      `stamp ${WORKDIR}/.devin-outpost-stamps/${SESSION_ID} is missing`,
    );
    expect(missing.start.stdout).toContain(
      `stamp ${STATE_DIR}/${SESSION_ID}/outpost_stamp is missing`,
    );
    await workingPid(id);

    // Both stamps survived the stop, as persistent storage should keep them.
    await execContainer(id, [
      "sh",
      "-c",
      `mkdir -p ${WORKDIR}/.devin-outpost-stamps && touch ${WORKDIR}/.devin-outpost-stamps/${SESSION_ID} ${STATE_DIR}/${SESSION_ID}/outpost_stamp`,
    ]);
    const present = await runDispatched(id, scripts, resume);
    expect(present.start.exitCode, present.start.stdout).toBe(0);
    expect(present.start.stdout).not.toContain("Warning");
    await workingPid(id);
    expect(await remoteCount(id)).toBe(1);
  });

  it("does not warn about stamps for a new session", async () => {
    const { id, scripts } = await setup();
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode).toBe(0);
    expect(start.stdout).not.toContain("Warning");
  });

  it("fails with connect-timeout and stops a remote that never connects", async () => {
    const { id, scripts, statusScript, attachedScript } = await setup({
      connect_timeout: "2",
    });
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode).toBe(0);
    const pid = await workingPid(id);
    expect(await waitForState(id, /^failed /, 8000)).toBe(
      "failed connect-timeout",
    );
    await waitFor(async () => !(await processAlive(id, pid)), "remote exit");
    await waitFor(
      async () => (await allRecords(id)).length === 0,
      "the supervisor to exit",
    );
    // The remote's exit after the timeout must not be recorded as done.
    expect(await readState(id)).toBe("failed connect-timeout");
    expect(await statusOf(id, statusScript)).toBe("failed connect-timeout");
    expect(await statusOf(id, attachedScript)).toBe("stopped");
    expect(await runtimeDirs(id)).toEqual([]);
    expect(await remoteRuns(id)).toBe(1);
  });

  it(
    "kills a remote that ignores TERM after the connect timeout",
    async () => {
      const { id, scripts } = await setup({ connect_timeout: "1" });
      await remoteBehavior(id, "trap '' TERM");
      const { start } = await runDispatched(id, scripts);
      expect(start.exitCode).toBe(0);
      const pid = await workingPid(id);
      expect(await waitForState(id, /^failed /, 5000)).toBe(
        "failed connect-timeout",
      );
      await waitFor(
        async () => !(await processAlive(id, pid)),
        "remote SIGKILL",
        20000,
      );
      await waitFor(
        async () => (await allRecords(id)).length === 0,
        "the supervisor to exit",
      );
      expect(await readState(id)).toBe("failed connect-timeout");
    },
    60 * 1000,
  );

  it("reports serving once the coloured connected line is logged", async () => {
    const { id, scripts, statusScript, attachedScript } = await setup({
      connect_timeout: "2",
    });
    // The remote logs the connected line the way devin-remote colours it,
    // after the line that only means it is about to dial.
    await remoteBehavior(
      id,
      `echo "Server running, waiting for connections..." >&2; printf '${CONNECTED_LINE}\\n' >&2`,
    );
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode).toBe(0);
    const pid = await workingPid(id);
    await waitFor(
      async () => (await statusOf(id, statusScript)) === "serving",
      "serving",
    );
    const raw = await readFileContainer(id, LOG_FILE);
    expect(raw).toContain("\x1b[");
    expect(raw).not.toContain("connected to outpost gateway endpoint=");
    expect(await statusOf(id, attachedScript)).toBe("attached");

    // The same with busybox sed, as on a minimal image.
    await stubBinary(id, "/usr/local/bin/sed", 'exec busybox sed "$@"');
    expect(await statusOf(id, statusScript)).toBe("serving");

    // A connected remote outlives the connect timeout.
    await Bun.sleep(4000);
    expect(await readState(id)).toBe(`working ${pid}`);
    expect(await processAlive(id, pid)).toBe(true);
  });

  it("records done 0 when the session ends and does not restart the remote", async () => {
    const { id, scripts, statusScript, attachedScript } = await setup();
    await remoteBehavior(id, "exit 0");
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode).toBe(0);
    expect(await waitForState(id, /^done \d+$/)).toBe("done 0");
    await waitFor(
      async () => (await allRecords(id)).length === 0,
      "identity record removal",
    );
    await Bun.sleep(1500);
    expect(await readState(id)).toBe("done 0");
    expect(await remoteRuns(id)).toBe(1);
    expect(await remoteCount(id)).toBe(0);
    expect(await runtimeDirs(id)).toEqual([]);
    expect(await statusOf(id, statusScript)).toBe("done 0");
    expect(await statusOf(id, attachedScript)).toBe("stopped");
  });

  it("records the exit code when the remote fails", async () => {
    const { id, scripts, statusScript } = await setup();
    await remoteBehavior(id, "exit 3");
    const { start } = await runDispatched(id, scripts);
    expect(start.exitCode).toBe(0);
    expect(await waitForState(id, /^done \d+$/)).toBe("done 3");
    expect(await statusOf(id, statusScript)).toBe("done 3");
    await waitFor(
      async () => (await allRecords(id)).length === 0,
      "identity record removal",
    );
    expect(await runtimeDirs(id)).toEqual([]);
  });

  it("stops the remote on workspace stop without publishing a marker", async () => {
    const { id, scripts, attachedScript } = await setup();
    const first = await runDispatched(id, scripts);
    expect(first.start.exitCode).toBe(0);
    const { supervisorPid, remotePid } = await liveIdentity(id);
    expect(await statusOf(id, attachedScript)).toBe("attached");

    const stopped = await execContainer(id, ["bash", "-c", scripts.stop]);
    expect(stopped.exitCode, stopped.stdout).toBe(0);
    expect(stopped.stdout).toContain(
      `Stopping previous Devin remote (pid ${remotePid})`,
    );
    expect(await processAlive(id, supervisorPid)).toBe(false);
    expect(await processAlive(id, remotePid)).toBe(false);
    expect(await exists(id, STATE_FILE)).toBe(false);
    expect(await runtimeDirs(id)).toEqual([]);
    expect(await exists(id, CLEANUP_MARKER)).toBe(false);
    expect(await allRecords(id)).toEqual([]);
    expect(await statusOf(id, attachedScript)).toBe("stopped");

    // A later start must not inherit the stop's marker or state.
    const next = await runDispatched(id, scripts);
    expect(next.start.exitCode).toBe(0);
    await workingPid(id);
    expect(await remoteCount(id)).toBe(1);
  });

  it("stops the remote on TERM without recording a terminal state", async () => {
    const { id, scripts } = await setup();
    await runDispatched(id, scripts);
    const state = await readState(id);
    expect(state).toMatch(/^working \d+$/);
    const { supervisorPid } = await liveIdentity(id);

    await execContainer(id, ["kill", "-TERM", supervisorPid]);
    await waitFor(
      async () => !(await processAlive(id, supervisorPid)),
      "supervisor exit",
    );
    expect(await remoteCount(id)).toBe(0);
    expect(await allRecords(id)).toEqual([]);
    expect(await runtimeDirs(id)).toEqual([]);
    expect(await readState(id)).toBe(state);
  });

  it("stops a remote whose supervisor was SIGKILLed, so the next start runs only one", async () => {
    const { id, scripts } = await setup();
    const first = await runDispatched(id, scripts);
    expect(first.start.exitCode).toBe(0);
    const { supervisorPid, remotePid } = await liveIdentity(id);

    await execContainer(id, ["kill", "-KILL", supervisorPid]);
    await waitFor(
      async () => !(await processAlive(id, supervisorPid)),
      "supervisor exit",
    );
    expect(await processAlive(id, remotePid)).toBe(true);

    const second = await runDispatched(id, scripts);
    expect(second.preInstall.stdout).toContain(
      `Stopping previous Devin remote (pid ${remotePid})`,
    );
    expect(second.start.exitCode, second.start.stdout).toBe(0);
    expect(await processAlive(id, remotePid)).toBe(false);
    expect(await remoteCount(id)).toBe(1);
    expect(await recordsIn(id, SUPERVISORS_DIR)).toHaveLength(1);
    expect(await recordsIn(id, REMOTES_DIR)).toHaveLength(1);
  });

  it("runs nothing from a supervisor launched before a newer cleanup", async () => {
    const { id, scripts } = await setup();
    const first = await runDispatched(id, scripts);
    expect(first.start.exitCode).toBe(0);
    const firstCleanupId = (await readFileContainer(id, CLEANUP_MARKER)).trim();
    const cleanup = await execContainer(id, ["bash", "-c", scripts.preInstall]);
    expect(cleanup.exitCode).toBe(0);
    expect(await remoteCount(id)).toBe(0);
    const supervisor = await readFileContainer(
      id,
      `${MODULE_DIR}/scripts/supervise.sh`,
    );
    expect(supervisor).not.toContain(firstCleanupId);
    for (const args of [
      [firstCleanupId, cachedBinary(), "/tmp/agent-relay-devin-0.late"],
      [],
    ]) {
      const stale = await execContainer(id, [
        "env",
        ...DISPATCH_ENV,
        "bash",
        `${MODULE_DIR}/scripts/supervise.sh`,
        ...args,
      ]);
      expect(stale.exitCode, args.join(" ")).not.toBe(0);
      expect(await remoteCount(id)).toBe(0);
      expect(await allRecords(id)).toEqual([]);
      expect(await exists(id, STATE_FILE)).toBe(false);
    }
  });

  it("reports orphaned when the recorded pid is gone or is not the remote", async () => {
    const { id, statusScript, attachedScript } = await setup();
    await execContainer(id, ["mkdir", "-p", MODULE_DIR]);
    const sleeper = await execContainer(id, [
      "sh",
      "-c",
      "sleep 60 >/dev/null 2>&1 & echo $!",
    ]);
    for (const pid of ["999999", sleeper.stdout.trim()]) {
      await writeFileContainer(id, STATE_FILE, `working ${pid}\n`, {
        user: "root",
      });
      expect(await statusOf(id, statusScript), pid).toBe("orphaned");
      expect(await statusOf(id, attachedScript), pid).toBe("stopped");
    }
    await execContainer(id, ["rm", "-f", STATE_FILE]);
    expect(await statusOf(id, statusScript)).toBe("pending");
    expect(await statusOf(id, attachedScript)).toBe("stopped");
    // An empty file, as a vanished or truncated one reads, is pending too.
    await writeFileContainer(id, STATE_FILE, "", { user: "root" });
    expect(await statusOf(id, statusScript)).toBe("pending");
  });

  it("ignores a previous run's connected line on a resume", async () => {
    const { id, scripts, statusScript } = await setup({ connect_timeout: "2" });
    // The log survived the stop; its last line is the previous run's
    // connected line.
    await execContainer(id, ["mkdir", "-p", `${MODULE_DIR}/logs`]);
    await execContainer(id, [
      "sh",
      "-c",
      `printf '${CONNECTED_LINE}\\n' >${LOG_FILE}`,
    ]);
    const { start } = await runDispatched(id, scripts, [
      "AGENT_RELAY_DEVIN_SESSION_KIND=resume",
    ]);
    expect(start.exitCode).toBe(0);
    const pid = await workingPid(id);
    expect(await statusOf(id, statusScript)).toBe("working");
    expect(await readFileContainer(id, LOG_FILE)).not.toContain("endpoint");
    expect(await waitForState(id, /^failed /, 8000)).toBe(
      "failed connect-timeout",
    );
    await waitFor(async () => !(await processAlive(id, pid)), "remote exit");
  });
});
