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
  const install = byDisplayName["Happy: Install Script"];
  const start = byDisplayName["Happy: Start Script"];
  if (!install) {
    throw new Error("install script not found in terraform state");
  }
  if (!start) {
    throw new Error("start script not found in terraform state");
  }
  return { install, start };
};

const HAPPY_BIN_PATH =
  "/root/.coder-modules/gojnimer6553/happy/npm/node_modules/.bin/happy";

const installFakeHappyBinary = async (id: string, script: string) => {
  await execContainer(id, [
    "mkdir",
    "-p",
    "/root/.coder-modules/gojnimer6553/happy/npm/node_modules/.bin",
  ]);
  await writeFileContainer(id, HAPPY_BIN_PATH, script);
  await execContainer(id, ["chmod", "755", HAPPY_BIN_PATH]);
};

// Issues one HTTP GET from inside the container (no curl dependency: the
// test image only guarantees node) and reports status/body.
const httpGetInContainer = async (
  id: string,
  port: number,
  path: string,
  timeoutMs = 30000,
): Promise<{ status: number; body: string }> => {
  const script = [
    'const http = require("http");',
    `const req = http.get({ host: "127.0.0.1", port: ${port}, path: ${JSON.stringify(path)}, timeout: ${timeoutMs} }, (res) => {`,
    '  let body = "";',
    '  res.on("data", (c) => (body += c));',
    '  res.on("end", () => {',
    '    console.log("STATUS:" + res.statusCode);',
    '    console.log("BODY_START");',
    "    console.log(body);",
    "    process.exit(0);",
    "  });",
    "});",
    'req.on("timeout", () => { console.log("STATUS:0"); process.exit(0); });',
    'req.on("error", (e) => { console.log("ERROR:" + e.message); process.exit(0); });',
  ].join("\n");
  const output = await execContainer(id, ["node", "-e", script]);
  const status = Number(/STATUS:(\d+)/.exec(output.stdout)?.[1] ?? "0");
  const bodyIdx = output.stdout.indexOf("BODY_START\n");
  const body =
    bodyIdx === -1 ? "" : output.stdout.slice(bodyIdx + "BODY_START\n".length);
  return { status, body };
};

const waitForHealthy = async (
  id: string,
  port: number,
  timeoutMs = 30000,
): Promise<void> => {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const { status, body } = await httpGetInContainer(
      id,
      port,
      "/healthz",
      3000,
    );
    if (status === 200 && body.trim() === "ok") return;
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error(`Timed out waiting for port ${port}'s /healthz to report ok`);
};

// Fake happy binary: mimics the real CLI's interactive auth prompt closely
// enough to exercise this module's tmux-automation (send "1", capture a
// happy://terminal?... link) without a real npm install or network call.
// Each invocation embeds a unique token so tests can prove a fresh link is
// minted on every open.
const FAKE_HAPPY_BINARY = [
  "#!/bin/bash",
  'if [ "$1" = "auth" ]; then',
  '  echo "How would you like to authenticate?"',
  '  echo ""',
  '  echo "\xe2\x80\xba 1. Mobile App"',
  '  echo "  2. Web Browser"',
  "  read -r -n1 choice",
  '  echo ""',
  '  if [ "$choice" = "1" ]; then',
  '    echo "Mobile Authentication"',
  '    token="FAKE_$$_$(date +%s%N)"',
  '    echo "happy://terminal?$token"',
  '    echo "Waiting for authentication.."',
  "    sleep 3600",
  "  else",
  "    exit 1",
  "  fi",
  'elif [ "$1" = "claude" ]; then',
  '  echo "claude-started"',
  "  sleep 3600",
  "fi",
].join("\n");

// Mimics the prompt, accepts the "1" keypress, then crashes instead of
// producing a pairing link. Since the wrapped shell command is
// "happy_bin auth login --force && happy_bin claude", a non-zero exit here
// short-circuits the "&&" and the tmux session's pane process (and with it,
// by default, the session itself) exits shortly after -- exercising the
// "session died before producing a link" failure path distinctly from a
// plain prompt-format-mismatch timeout.
const FAKE_HAPPY_BINARY_CRASHES_AFTER_PROMPT = [
  "#!/bin/bash",
  'if [ "$1" = "auth" ]; then',
  '  echo "How would you like to authenticate?"',
  '  echo ""',
  '  echo "\xe2\x80\xba 1. Mobile App"',
  '  echo "  2. Web Browser"',
  "  read -r -n1 choice",
  '  echo ""',
  '  echo "boom: simulated crash"',
  "  exit 1",
  "fi",
].join("\n");

setDefaultTimeout(240 * 1000);

describe("happy", async () => {
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
        "⏭️  install=false; skipping Happy installation.",
      );

      // The start script should fail fast: no happy binary was ever installed.
      const startOutput = await execContainer(id, ["bash", "-c", start]);
      expect(startOutput.exitCode).not.toBe(0);
      expect(startOutput.stderr + startOutput.stdout).toContain(
        "happy binary not found",
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
      // A real (non-root, sudo-less) user with a proper writable $HOME --
      // "nobody"'s $HOME is the unwritable "/nonexistent", which breaks
      // coder-utils' own log-directory setup before this module's install
      // script even runs. The install script should detect it has no way
      // to gain privileges and fail fast, rather than let apt-get itself
      // fail with a confusing permissions error.
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

  it("mints a fresh pairing link on every open and leaves /healthz side-effect-free", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
      port: 4120,
      tmux_session: "happy-test-1",
    });
    const { install, start } = collectScripts(state);

    const id = await runContainer("node:22-bookworm-slim");
    try {
      await writeCoder(id, "#!/bin/bash\nexit 0\n");
      await execContainer(id, [
        "bash",
        "-c",
        "apt-get update && apt-get install -y --no-install-recommends tmux",
      ]);
      await execContainer(id, ["bash", "-c", install]);
      await installFakeHappyBinary(id, FAKE_HAPPY_BINARY);
      // install=false skips the real "happy" install (we use the fake
      // binary above), but the pairing server still needs "qrcode" -- the
      // real install script would normally install it alongside happy.
      await execContainer(id, [
        "bash",
        "-c",
        "cd /root/.coder-modules/gojnimer6553/happy/npm && npm install --no-audit --no-fund qrcode@1.5.4",
      ]);

      const output = await execContainer(id, ["bash", "-c", start]);
      expect(output.exitCode).toBe(0);

      await waitForHealthy(id, 4120);

      // /healthz must never trigger the pairing cycle: hit it several times
      // and confirm no tmux session gets created as a side effect.
      for (let i = 0; i < 5; i++) {
        await httpGetInContainer(id, 4120, "/healthz");
      }
      const sessionsBeforeOpen = await execContainer(id, [
        "bash",
        "-c",
        "tmux list-sessions 2>&1 || true",
      ]);
      expect(sessionsBeforeOpen.stdout).not.toContain("happy-test-1");

      const first = await httpGetInContainer(id, 4120, "/", 30000);
      expect(first.status).toBe(200);
      const firstMatch = /happy:\/\/terminal\?[A-Za-z0-9_]+/.exec(first.body);
      expect(firstMatch).not.toBeNull();
      expect(first.body).toContain("data:image/png;base64,");

      const second = await httpGetInContainer(id, 4120, "/", 30000);
      expect(second.status).toBe(200);
      const secondMatch = /happy:\/\/terminal\?[A-Za-z0-9_]+/.exec(second.body);
      if (!secondMatch) {
        console.log("SECOND BODY:\n" + second.body);
        const pairingLog = await readFileContainer(
          id,
          "/root/.coder-modules/gojnimer6553/happy/logs/pairing.log",
        ).catch((e) => "(failed to read pairing.log: " + e + ")");
        console.log("PAIRING LOG:\n" + pairingLog);
      }
      expect(secondMatch).not.toBeNull();

      // A different link each time -- proves the second open genuinely
      // killed the previous session and drove a brand new pairing cycle,
      // not just re-served a cached result.
      expect(secondMatch![0]).not.toBe(firstMatch![0]);
    } finally {
      await removeContainer(id);
    }
  }, 60000);

  it("surfaces a clear error quickly when happy's tmux session dies before pairing completes", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install: false,
      port: 4122,
      tmux_session: "happy-test-3",
    });
    const { install, start } = collectScripts(state);

    const id = await runContainer("node:22-bookworm-slim");
    try {
      await writeCoder(id, "#!/bin/bash\nexit 0\n");
      await execContainer(id, [
        "bash",
        "-c",
        "apt-get update && apt-get install -y --no-install-recommends tmux",
      ]);
      await execContainer(id, ["bash", "-c", install]);
      await installFakeHappyBinary(id, FAKE_HAPPY_BINARY_CRASHES_AFTER_PROMPT);
      await execContainer(id, [
        "bash",
        "-c",
        "cd /root/.coder-modules/gojnimer6553/happy/npm && npm install --no-audit --no-fund qrcode@1.5.4",
      ]);

      const output = await execContainer(id, ["bash", "-c", start]);
      expect(output.exitCode).toBe(0);

      await waitForHealthy(id, 4122);

      const started = Date.now();
      const page = await httpGetInContainer(id, 4122, "/", 30000);
      const elapsedMs = Date.now() - started;

      expect(page.status).toBe(200);
      expect(page.body).toContain("exited before it finished pairing");
      // The fake binary crashes almost immediately after the "1" keypress --
      // this should fail fast via the has-session check, not wait out the
      // full 20s pairing-url timeout.
      expect(elapsedMs).toBeLessThan(15000);
    } finally {
      await removeContainer(id);
    }
  }, 60000);

  it("installs Happy via npm and serves a real pairing QR/link", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      port: 4121,
      tmux_session: "happy-test-2",
    });
    const { install, start } = collectScripts(state);

    const id = await runContainer("node:22-bookworm-slim");
    try {
      await writeCoder(id, "#!/bin/bash\nexit 0\n");
      await execContainer(id, [
        "bash",
        "-c",
        "apt-get update && apt-get install -y --no-install-recommends tmux",
      ]);

      const installOutput = await execContainer(id, ["bash", "-c", install]);
      if (installOutput.exitCode !== 0) {
        console.log("STDOUT:\n" + installOutput.stdout);
        console.log("STDERR:\n" + installOutput.stderr);
      }
      expect(installOutput.exitCode).toBe(0);
      expect(installOutput.stdout).toContain("🥳 Happy has been installed to");

      const startOutput = await execContainer(id, ["bash", "-c", start]);
      expect(startOutput.exitCode).toBe(0);
      expect(startOutput.stdout).toContain("Happy pairing server started");

      await waitForHealthy(id, 4121);

      // Real network call to Happy's hosted auth API happens here (there is
      // no offline pairing path) -- we only need the resulting link/QR, not
      // an actual phone to complete pairing, so this doesn't block on that.
      const page = await httpGetInContainer(id, 4121, "/", 45000);
      if (page.status !== 200) {
        const log = await readFileContainer(
          id,
          "/root/.coder-modules/gojnimer6553/happy/logs/pairing.log",
        ).catch(() => "(no pairing log)");
        console.log("PAIRING LOG:\n" + log);
      }
      expect(page.status).toBe(200);
      expect(page.body).toMatch(/happy:\/\/terminal\?[A-Za-z0-9_-]+/);
      expect(page.body).toContain("data:image/png;base64,");
    } finally {
      await removeContainer(id);
    }
  }, 240000);
});
