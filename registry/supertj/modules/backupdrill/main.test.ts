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
const ROOT_MODULE_BIN =
  "/root/.coder-modules/supertj/backupdrill/npm-global/bin/backupdrill";

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

// Stand-in npm: records its arguments in /tmp/npm-args and writes `cli` as
// the backupdrill executable under the --prefix it was given, so these tests
// need no network access.
const writeFakeNpm = (id: string, path: string, cli: string) =>
  writeExecutable(
    id,
    path,
    [
      "#!/usr/bin/env bash",
      'echo "$@" > /tmp/npm-args',
      'prefix=""',
      'while [ $# -gt 0 ]; do [ "$1" = "--prefix" ] && prefix="$2"; shift; done',
      'mkdir -p "$prefix/bin"',
      `echo '${Buffer.from(cli).toString("base64")}' | base64 -d > "$prefix/bin/backupdrill"`,
      'chmod +x "$prefix/bin/backupdrill"',
    ].join("\n"),
  );

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
      ["cat", "/home/node/.coder-modules/supertj/backupdrill/logs/install.log"],
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
    await writeFakeNpm(id, "/usr/local/bin/npm", "#!/bin/sh\necho 2.7.1\n");
    // Stand-in node that just runs the script it is given.
    await writeExecutable(id, "/usr/local/bin/node", '#!/bin/sh\nexec "$@"\n');

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
    expect(args.stdout).toContain("--engine-strict");
    expect(args.stdout).toContain("--ignore-scripts");
    expect(args.stdout).toContain("backupdrill@2.7.1");

    const launcher = await execContainer(id, [
      "cat",
      `${SCRIPT_BIN_DIR}/backupdrill`,
    ]);
    expect(launcher.stdout).toContain(
      `exec "/usr/local/bin/node" "${ROOT_MODULE_BIN}" "$@"`,
    );
  });

  it("keeps using the nvm Node.js it installed with, even with an older system Node.js", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
    });
    const id = await startWorkspace("debian:bookworm-slim", "root");
    // A stand-in nvm: its node and npm are only on PATH after nvm.sh is
    // sourced. Each stand-in node prints which one ran.
    const mkdir = await execContainer(id, [
      "mkdir",
      "-p",
      "/opt/nvm-node/bin",
      "/root/.nvm",
    ]);
    expect(mkdir.exitCode).toBe(0);
    await writeExecutable(
      id,
      "/opt/nvm-node/bin/node",
      "#!/bin/sh\necho 2.8.0\n",
    );
    await writeExecutable(
      id,
      "/usr/local/bin/node",
      "#!/bin/sh\necho system-node\n",
    );
    await writeFakeNpm(id, "/opt/nvm-node/bin/npm", "#!/usr/bin/env node\n");
    await writeFileContainer(
      id,
      "/root/.nvm/nvm.sh",
      'export PATH="/opt/nvm-node/bin:$PATH"\n',
      { user: "root" },
    );

    const result = await runInstall(id, installScript(state), "root");
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("Installed backupdrill 2.8.0.");

    // Without nvm loaded, the npm-generated executable picks up the system
    // Node.js...
    const direct = await execContainer(id, [
      "bash",
      "-c",
      `${ROOT_MODULE_BIN} --version`,
    ]);
    expect(direct.stdout.trim()).toBe("system-node");

    // ...while the launcher on the agent's PATH runs the nvm one.
    const viaLauncher = await execContainer(id, [
      "bash",
      "-c",
      `${SCRIPT_BIN_DIR}/backupdrill --version`,
    ]);
    expect(viaLauncher.exitCode).toBe(0);
    expect(viaLauncher.stdout.trim()).toBe("2.8.0");
  });

  it("fails when the installed CLI does not run", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
    });
    const id = await startWorkspace("debian:bookworm-slim", "root");
    await writeFakeNpm(id, "/usr/local/bin/npm", "#!/bin/sh\nexit 42\n");

    const result = await runInstall(id, installScript(state), "root");
    expect(result.exitCode).not.toBe(0);
    expect(result.stdout).toContain("--version' failed");
    expect(result.stdout).not.toContain("Installed backupdrill");
  });
});
