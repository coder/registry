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
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
} from "~test";

setDefaultTimeout(120_000);
const commit = "a".repeat(40);
const root = "/root/.coder-modules/coder/vscode-web";
let container: string | undefined;

beforeAll(() => runTerraformInit(import.meta.dir));
afterEach(async () => {
  if (container) await removeContainer(container);
  container = undefined;
});

// Test doubles exercise the rendered scripts, never claim OAuth/browser coverage.
async function prepareContainer(installPrefix = root) {
  container = await runContainer("ubuntu:22.04");
  const setup = await execContainer(container, [
    "bash",
    "-c",
    `
mkdir -p '${installPrefix}/bin' '${root}/cli/serve-web/${commit}/bin'
printf '%s\n' '${commit}' > '${root}/commit'
cat > /usr/local/bin/coder <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat > /usr/local/bin/curl <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "--fail" ]; then exit 0; fi
echo 'unexpected download' >&2
exit 22
EOF
cat > '${installPrefix}/bin/code-${commit}' <<'EOF'
#!/usr/bin/env bash
printf 'CLI_ARG:%s\n' "$@"
exec sleep infinity
EOF
cat > '${root}/cli/serve-web/${commit}/bin/code-server' <<'EOF'
#!/usr/bin/env bash
printf 'SERVER_ARG:%s\n' "$@" >> /root/server-args
EOF
chmod +x /usr/local/bin/coder /usr/local/bin/curl '${installPrefix}/bin/code-${commit}' '${root}/cli/serve-web/${commit}/bin/code-server'
`,
  ]);
  expect(setup.exitCode, setup.stderr).toBe(0);
  return container;
}

describe("vscode-web CLI", () => {
  it("reuses a pinned cache, installs extensions and preserves quoted paths", async () => {
    const prefix = "/root/custom cli";
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      port: 31338,
      accept_license: true,
      use_cli: true,
      use_cached: true,
      commit_id: commit,
      install_prefix: prefix,
      telemetry_level: "off",
      log_path: "/root/logs/it's vscode.log",
      extensions: '["publisher.extension"]',
      settings: '{"editor.fontSize":17}',
      folder: "/root/project's folder",
    });
    const id = await prepareContainer(prefix);
    const install = await execContainer(id, [
      "bash",
      "-c",
      findResourceInstance(state, "coder_script", "install_script").script,
    ]);
    expect(install.exitCode, install.stderr + install.stdout).toBe(0);
    const extensionArgs = await execContainer(id, ["cat", "/root/server-args"]);
    expect(extensionArgs.stdout).toContain("SERVER_ARG:publisher.extension");
    const settings = await execContainer(id, [
      "cat",
      "/root/.vscode-server/data/Machine/settings.json",
    ]);
    expect(JSON.parse(settings.stdout)).toEqual({
      "editor.fontSize": 17,
      "telemetry.telemetryLevel": "off",
    });
    const start = await execContainer(id, [
      "bash",
      "-c",
      findResourceInstance(state, "coder_script", "start_script").script,
    ]);
    expect(start.exitCode, start.stderr + start.stdout).toBe(0);
    const log = await execContainer(id, ["cat", "/root/logs/it's vscode.log"]);
    expect(log.stdout).toContain("CLI_ARG:serve-web");
    expect(log.stdout).toContain(`CLI_ARG:${root}/cli`);
    expect(log.stdout).toContain("CLI_ARG:--disable-telemetry");
    expect(log.stdout).toContain(`CLI_ARG:${commit}`);
  });

  it("starts offline from the recorded version without a download", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      port: 31338,
      accept_license: true,
      use_cli: true,
      offline: true,
    });
    const id = await prepareContainer();
    for (const name of ["install_script", "start_script"]) {
      const result = await execContainer(id, [
        "bash",
        "-c",
        findResourceInstance(state, "coder_script", name).script,
      ]);
      expect(result.exitCode, result.stderr + result.stdout).toBe(0);
      expect(result.stdout + result.stderr).not.toContain(
        "unexpected download",
      );
    }
  });

  it("fails offline when the server cache is incomplete", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      port: 31338,
      accept_license: true,
      use_cli: true,
      offline: true,
    });
    const id = await prepareContainer();
    await execContainer(id, [
      "rm",
      `${root}/cli/serve-web/${commit}/bin/code-server`,
    ]);
    const result = await execContainer(id, [
      "bash",
      "-c",
      findResourceInstance(state, "coder_script", "install_script").script,
    ]);
    expect(result.exitCode).not.toBe(0);
    expect(result.stdout + result.stderr).toContain(
      "requires both the CLI and server",
    );
  });

  it("propagates download errors without committing a new version", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      port: 31338,
      accept_license: true,
      use_cli: true,
      commit_id: "b".repeat(40),
    });
    const id = await prepareContainer();
    const result = await execContainer(id, [
      "bash",
      "-c",
      findResourceInstance(state, "coder_script", "install_script").script,
    ]);
    expect(result.exitCode).not.toBe(0);
    expect(result.stdout + result.stderr).toContain("unexpected download");
    const marker = await execContainer(id, ["cat", `${root}/commit`]);
    expect(marker.exitCode).not.toBe(0);
    const start = await execContainer(id, [
      "bash",
      "-c",
      findResourceInstance(state, "coder_script", "start_script").script,
    ]);
    expect(start.exitCode).not.toBe(0);
    expect(start.stdout).not.toContain("VS Code Web is ready");
  });
  it("reports a launcher that exits before becoming ready", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      port: 31338,
      accept_license: true,
      use_cli: true,
      offline: true,
    });
    const id = await prepareContainer();
    await execContainer(id, [
      "bash",
      "-c",
      `
mkdir -p '${root}/logs' '${root}/scripts'
printf '#!/usr/bin/env bash\\nexit 42\\n' > '${root}/bin/code-${commit}'
printf '#!/usr/bin/env bash\\nexit 7\\n' > /usr/local/bin/curl
`,
    ]);
    const start = await execContainer(id, [
      "bash",
      "-c",
      findResourceInstance(state, "coder_script", "start_script").script,
    ]);
    expect(start.exitCode).not.toBe(0);
    expect(start.stdout + start.stderr).toContain("exited during startup");
    expect(start.stdout).not.toContain("VS Code Web is ready");
  });
  it("rejects unsupported platforms before downloading", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      accept_license: true,
      use_cli: true,
      commit_id: commit,
    });
    const id = await prepareContainer();
    await execContainer(id, ["touch", "/etc/alpine-release"]);
    const result = await execContainer(id, [
      "bash",
      "-c",
      findResourceInstance(state, "coder_script", "install_script").script,
    ]);
    expect(result.exitCode).not.toBe(0);
    expect(result.stdout + result.stderr).toContain(
      "requires a glibc-based workspace",
    );
    expect(result.stdout + result.stderr).not.toContain("unexpected download");
  });
});
