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
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  writeCoder,
  writeFileContainer,
  type TerraformState,
} from "~test";

// The happy-path test runs a real `npm install` from the public registry.
setDefaultTimeout(4 * 60 * 1000);

const SCRIPT_BIN_DIR = "/tmp/coder-script-bin";

let containers: string[] = [];
afterEach(
  async () => {
    for (const id of containers) {
      await removeContainer(id).catch(() => {});
    }
    containers = [];
  },
  { timeout: 30 * 1000 },
);

const installScript = (state: TerraformState): string => {
  const resource = state.resources.find(
    (r) => r.type === "coder_script" && r.name === "install_script",
  );
  if (!resource) {
    throw new Error("install script not found in terraform state");
  }
  return resource.instances[0].attributes.script as string;
};

// Starts a container with a no-op `coder` CLI (coder-utils calls
// `coder exp sync`) and the agent's script bin directory in place.
const startWorkspace = async (image: string, user: string) => {
  const id = await runContainer(image);
  containers.push(id);
  await writeCoder(id, "#!/bin/sh\nexit 0\n");
  const mkdir = await execContainer(
    id,
    [
      "sh",
      "-c",
      `mkdir -p ${SCRIPT_BIN_DIR} && chown ${user} ${SCRIPT_BIN_DIR}`,
    ],
    ["--user", "root"],
  );
  expect(mkdir.exitCode).toBe(0);
  return id;
};

const runInstall = (id: string, script: string, user: string) =>
  execContainer(
    id,
    ["bash", "-c", script],
    ["--user", user, "-e", `CODER_SCRIPT_BIN_DIR=${SCRIPT_BIN_DIR}`],
  );

const writeExecutable = async (id: string, path: string, content: string) => {
  await writeFileContainer(id, path, content, { user: "root" });
  const chmod = await execContainer(
    id,
    ["chmod", "755", path],
    ["--user", "root"],
  );
  expect(chmod.exitCode).toBe(0);
};

describe("backupdrill", () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  testRequiredVariables(import.meta.dir, {
    agent_id: "test-agent",
  });

  it("installs the latest 2.x as a non-root user and skips it on the next start", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
    });
    const script = installScript(state);
    const id = await startWorkspace("node:22-bookworm-slim", "node");

    const first = await runInstall(id, script, "node");
    if (first.exitCode !== 0) {
      console.log(first.stdout, first.stderr);
    }
    expect(first.exitCode).toBe(0);
    expect(first.stdout).toContain("Installing backupdrill@2");

    const version = await execContainer(
      id,
      ["bash", "-c", `${SCRIPT_BIN_DIR}/backupdrill --version`],
      ["--user", "node"],
    );
    expect(version.exitCode).toBe(0);
    expect(version.stdout.trim()).toMatch(/^2\.\d+\.\d+$/);

    const log = await execContainer(
      id,
      [
        "cat",
        "/home/node/.coder-modules/backupdrill/backupdrill/logs/install.log",
      ],
      ["--user", "node"],
    );
    expect(log.stdout).toContain("Installed backupdrill 2.");

    const second = await runInstall(id, script, "node");
    expect(second.exitCode).toBe(0);
    expect(second.stdout).toContain("skipping the install");
    expect(second.stdout).not.toContain("Installing backupdrill@");
  });

  it("exits cleanly with a hint when npm is missing", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
    });
    const id = await startWorkspace("debian:bookworm-slim", "root");

    const result = await runInstall(id, installScript(state), "root");
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("npm was not found on PATH");
    expect(result.stdout).toContain("Skipping the backupdrill install");
  });

  it("leaves a matching backupdrill that is already on PATH alone", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
    });
    const id = await startWorkspace("debian:bookworm-slim", "root");
    await writeExecutable(
      id,
      "/usr/local/bin/backupdrill",
      "#!/bin/sh\necho 2.99.0\n",
    );

    const result = await runInstall(id, installScript(state), "root");
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain(
      "backupdrill 2.99.0 is already on PATH at /usr/local/bin/backupdrill",
    );
  });

  it("installs when the copy on PATH does not match, using the custom registry", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      backupdrill_version: "2.7.1",
      npm_registry_url: "https://npm.internal.example.com/",
    });
    const id = await startWorkspace("debian:bookworm-slim", "root");
    await writeExecutable(
      id,
      "/usr/local/bin/backupdrill",
      "#!/bin/sh\necho 2.6.0\n",
    );
    // Stand-in npm: records its arguments and drops a fake CLI into the
    // prefix it was given, so this test needs no network access.
    await writeExecutable(
      id,
      "/usr/local/bin/npm",
      [
        "#!/usr/bin/env bash",
        'echo "$@" > /tmp/npm-args',
        'prefix=""',
        'while [ $# -gt 0 ]; do [ "$1" = "--prefix" ] && prefix="$2"; shift; done',
        'mkdir -p "$prefix/bin"',
        'printf "#!/bin/sh\\necho 2.7.1\\n" > "$prefix/bin/backupdrill"',
        'chmod +x "$prefix/bin/backupdrill"',
      ].join("\n"),
    );

    const result = await runInstall(id, installScript(state), "root");
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain(
      "Found backupdrill 2.6.0 at /usr/local/bin/backupdrill, but backupdrill_version is 2.7.1",
    );
    expect(result.stdout).toContain("Installed backupdrill 2.7.1.");

    const args = await execContainer(id, ["cat", "/tmp/npm-args"]);
    expect(args.stdout).toContain(
      "--registry https://npm.internal.example.com/",
    );
    expect(args.stdout).toContain("--ignore-scripts");
    expect(args.stdout).toContain("backupdrill@2.7.1");

    const linked = await execContainer(id, [
      "readlink",
      `${SCRIPT_BIN_DIR}/backupdrill`,
    ]);
    expect(linked.stdout.trim()).toBe(
      "/root/.coder-modules/backupdrill/backupdrill/npm-global/bin/backupdrill",
    );
  });
});
