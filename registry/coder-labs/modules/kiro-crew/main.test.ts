import {
  afterEach,
  beforeAll,
  describe,
  expect,
  setDefaultTimeout,
  test,
} from "bun:test";
import {
  execContainer,
  readFileContainer,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  TerraformState,
} from "~test";
import { writeExecutable } from "../../../coder/modules/agentapi/test-util";
import path from "path";

interface ModuleScripts {
  pre_install?: string;
  install: string;
  post_install?: string;
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
  const install = byDisplayName["Kiro Crew: Install Script"];
  const start = byDisplayName["Kiro Crew: Start Script"];
  if (!install || !start) {
    throw new Error("install or start script not found in terraform state");
  }
  return {
    pre_install: byDisplayName["Kiro Crew: Pre-Install Script"],
    install,
    post_install: byDisplayName["Kiro Crew: Post-Install Script"],
    start,
  };
};

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

const moduleDir = path.resolve(import.meta.dir);
const moduleLogDir = "/home/coder/.coder-modules/coder-labs/kiro-crew/logs";

// Containers share the host network, so use ports unlikely to be in use.
const gatewayPort = "19899";
const redirectPort = "19898";

interface SetupProps {
  // Install mock kiro-cli and kirocrew binaries on PATH.
  withMocks?: boolean;
  moduleVariables?: Record<string, string>;
}

const setup = async (
  props?: SetupProps,
): Promise<{ id: string; scripts: ModuleScripts; state: TerraformState }> => {
  const state = await runTerraformApply(moduleDir, {
    agent_id: "foo",
    port: gatewayPort,
    redirect_port: redirectPort,
    ...props?.moduleVariables,
  });
  const scripts = collectScripts(state);

  const id = await runContainer("codercom/enterprise-node:latest");
  registerCleanup(async () => {
    if (process.env["DEBUG"] === "true" || process.env["DEBUG"] === "1") {
      console.log(`Not removing container ${id} in debug mode`);
      return;
    }
    await removeContainer(id);
  });

  // `coder exp sync` calls from the coder-utils wrappers need a coder binary.
  await writeExecutable({
    containerId: id,
    filePath: "/usr/bin/coder",
    content: "#!/bin/bash\nexit 0\n",
  });
  await writeExecutable({
    containerId: id,
    filePath: "/tmp/fake-gateway.py",
    content: await Bun.file(
      path.join(moduleDir, "testdata", "fake-gateway.py"),
    ).text(),
  });
  if (props?.withMocks) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/kiro-cli",
      content: await Bun.file(
        path.join(moduleDir, "testdata", "kiro-cli-mock.sh"),
      ).text(),
    });
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/kirocrew",
      content: await Bun.file(
        path.join(moduleDir, "testdata", "kirocrew-mock.sh"),
      ).text(),
    });
  }
  return { id, scripts, state };
};

const envPrefix = (env?: Record<string, string>) =>
  Object.entries(env ?? {})
    .map(([key, value]) => `export ${key}="${value.replace(/"/g, '\\"')}" && `)
    .join("");

const runScript = async (
  id: string,
  name: string,
  script: string,
  env?: Record<string, string>,
) => {
  const target = `/tmp/coder-utils-${name}.sh`;
  await writeExecutable({ containerId: id, filePath: target, content: script });
  return execContainer(id, ["bash", "-c", `${envPrefix(env)}${target}`]);
};

const runOrFail = async (
  id: string,
  name: string,
  script: string,
  env?: Record<string, string>,
) => {
  const resp = await runScript(id, name, script, env);
  if (resp.exitCode !== 0) {
    console.log(`script ${name} failed:`);
    console.log(resp.stdout);
    console.log(resp.stderr);
  }
  expect(resp.exitCode).toBe(0);
  return resp;
};

// Records curl arguments and copies a per-URL fixture to --output. Exits with
// failExitCode instead when it is non-zero.
const writeCurlMock = async (id: string, failExitCode = 0) => {
  await writeExecutable({
    containerId: id,
    filePath: "/usr/local/bin/curl",
    content: `#!/bin/bash
printf '%s\\n' "$*" >> /tmp/curl-args
out=""
url=""
while [ $# -gt 0 ]; do
  case "$1" in
    --output) out="$2"; shift ;;
    http*) url="$1" ;;
  esac
  shift
done
if [ ${failExitCode} -ne 0 ]; then
  exit ${failExitCode}
fi
case "$url" in
  https://cli.kiro.dev/install) cp /tmp/fixtures/kiro-cli-install.sh "$out" ;;
  https://download.crew.kiro.dev/cli.sh) cp /tmp/fixtures/kiro-crew-install.sh "$out" ;;
  *) exit 22 ;;
esac
`,
  });
};

// Fake installers that place binaries where the real installers do: kiro-cli
// in ~/.local/bin and kirocrew in the managed venv.
const writeInstallerFixtures = async (id: string) => {
  await execContainer(id, ["mkdir", "-p", "/tmp/fixtures"]);
  await writeExecutable({
    containerId: id,
    filePath: "/tmp/fixtures/kiro-cli-install.sh",
    content: `#!/bin/bash
echo "kiro-cli installer ran" >> /tmp/installers-ran
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\\necho "kiro-cli 9.9.9"\\n' > "$HOME/.local/bin/kiro-cli"
chmod +x "$HOME/.local/bin/kiro-cli"
`,
  });
  await writeExecutable({
    containerId: id,
    filePath: "/tmp/fixtures/kiro-crew-install.sh",
    content: `#!/bin/sh
echo "kiro-crew installer ran PYTHONPATH=\${PYTHONPATH-unset} pipx=$(command -v pipx)" >> /tmp/installers-ran
mkdir -p "$HOME/.kiro/crew-venv/bin"
cp /tmp/kirocrew-mock.sh "$HOME/.kiro/crew-venv/bin/kirocrew"
chmod +x "$HOME/.kiro/crew-venv/bin/kirocrew"
`,
  });
  await writeExecutable({
    containerId: id,
    filePath: "/tmp/kirocrew-mock.sh",
    content: await Bun.file(
      path.join(moduleDir, "testdata", "kirocrew-mock.sh"),
    ).text(),
  });
  // Pre-create the dedicated pipx so the test does not hit PyPI.
  await execContainer(id, [
    "bash",
    "-c",
    `mkdir -p "$HOME/.kiro/pipx-venv/bin" && printf '#!/bin/sh\\nexit 0\\n' > "$HOME/.kiro/pipx-venv/bin/pipx" && chmod +x "$HOME/.kiro/pipx-venv/bin/pipx"`,
  ]);
};

// Polls a URL from inside the container until curl reports the expected
// status code, then prints "<status> <redirect_url>".
const waitForStatus = async (id: string, url: string, status: string) => {
  const resp = await execContainer(id, [
    "bash",
    "-c",
    `for i in $(seq 1 100); do
       out=$(/usr/bin/curl -s -o /dev/null -w '%{http_code} %{redirect_url}' '${url}')
       case "$out" in ${status}*) echo "$out"; exit 0 ;; esac
       sleep 0.2
     done
     echo "last: $out"; exit 1`,
  ]);
  if (resp.exitCode !== 0) {
    console.log(resp.stdout);
    console.log(
      await execContainer(id, ["bash", "-c", `cat ${moduleLogDir}/*.log`]),
    );
  }
  expect(resp.exitCode).toBe(0);
  return resp.stdout.trim();
};

setDefaultTimeout(90 * 1000);

describe("kiro-crew", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("install-uses-cached-binaries", async () => {
    const { id, scripts } = await setup({ withMocks: true });
    await writeCurlMock(id, 22);
    await runOrFail(id, "install", scripts.install);
    const log = await readFileContainer(id, `${moduleLogDir}/install.log`);
    expect(log).toContain("Kiro CLI already installed: kiro-cli 0.0.0-test");
    expect(log).toContain("Kiro Crew already installed: /usr/bin/kirocrew");
    expect(log).toContain("Kiro Crew install completed.");
    const curl = await execContainer(id, ["test", "-e", "/tmp/curl-args"]);
    expect(curl.exitCode).not.toBe(0);
  });

  test("install-runs-installers-when-missing", async () => {
    const { id, scripts } = await setup();
    await writeInstallerFixtures(id);
    await writeCurlMock(id);
    await runOrFail(id, "install", scripts.install, {
      PYTHONPATH: "/should/be/unset",
    });
    const curlArgs = await readFileContainer(id, "/tmp/curl-args");
    expect(curlArgs).toContain("https://cli.kiro.dev/install");
    expect(curlArgs).toContain("https://download.crew.kiro.dev/cli.sh");
    const ran = await readFileContainer(id, "/tmp/installers-ran");
    expect(ran).toContain("kiro-cli installer ran");
    expect(ran).toContain(
      "kiro-crew installer ran PYTHONPATH=unset pipx=/home/coder/.local/bin/pipx",
    );
    const log = await readFileContainer(id, `${moduleLogDir}/install.log`);
    expect(log).toContain("Kiro CLI ready.");
    expect(log).toContain("Kiro Crew ready.");
  });

  test("install-reinstalls-when-use-cached-is-false", async () => {
    const { id, scripts } = await setup({
      withMocks: true,
      moduleVariables: { use_cached: "false" },
    });
    await writeInstallerFixtures(id);
    await writeCurlMock(id);
    await runOrFail(id, "install", scripts.install);
    const ran = await readFileContainer(id, "/tmp/installers-ran");
    expect(ran).toContain("kiro-cli installer ran");
    expect(ran).toContain("kiro-crew installer ran");
  });

  test("install-fails-when-download-fails", async () => {
    const { id, scripts } = await setup();
    await writeCurlMock(id, 22);
    const resp = await runScript(id, "install", scripts.install);
    expect(resp.exitCode).not.toBe(0);
    const log = await readFileContainer(id, `${moduleLogDir}/install.log`);
    expect(log).toContain("Kiro CLI installation failed.");
  });

  test("install-writes-extra-mcp-json", async () => {
    const extra = JSON.stringify({
      mcpServers: { demo: { command: "echo", args: ["it's"] } },
    });
    const { id, scripts } = await setup({
      withMocks: true,
      moduleVariables: { extra_mcp_json: extra },
    });
    await runOrFail(id, "install", scripts.install);
    const mcp = await readFileContainer(
      id,
      "/home/coder/.kiro/settings/mcp.json",
    );
    expect(JSON.parse(mcp)).toEqual(JSON.parse(extra));
  });

  test("install-merges-extra-mcp-json", async () => {
    const extra = JSON.stringify({
      mcpServers: { demo: { command: "new" } },
    });
    const { id, scripts } = await setup({
      withMocks: true,
      moduleVariables: { extra_mcp_json: extra },
    });
    await execContainer(id, [
      "bash",
      "-c",
      `mkdir -p ~/.kiro/settings && echo '{"mcpServers":{"coder":{"url":"u"},"demo":{"command":"old"}},"other":1}' > ~/.kiro/settings/mcp.json`,
    ]);
    await runOrFail(id, "install", scripts.install);
    const mcp = JSON.parse(
      await readFileContainer(id, "/home/coder/.kiro/settings/mcp.json"),
    );
    expect(mcp).toEqual({
      mcpServers: { coder: { url: "u" }, demo: { command: "new" } },
      other: 1,
    });
  });

  test("start-launches-gateway-and-redirector", async () => {
    const { id, scripts, state } = await setup({
      withMocks: true,
      moduleVariables: { allowed_origins: "https://extra.example.com" },
    });
    const dashboardOrigin = state.outputs.dashboard_origin.value as string;
    await runOrFail(id, "install", scripts.install);
    const start = await runOrFail(id, "start", scripts.start, {
      KIRO_AWS_BUILDER_ID_TOKEN: "builder-token",
    });
    expect(start.stdout).toContain("Kiro Crew gateway launch dispatched.");

    await waitForStatus(id, `http://127.0.0.1:${redirectPort}/healthz`, "200");
    const health = await execContainer(id, [
      "/usr/bin/curl",
      "-s",
      `http://127.0.0.1:${gatewayPort}/health`,
    ]);
    expect(health.stdout).toBe("fake-gateway");

    const redirect = await waitForStatus(
      id,
      `http://127.0.0.1:${redirectPort}/`,
      "302",
    );
    expect(redirect).toBe(`302 ${dashboardOrigin}/?token=test-token`);

    const gatewayEnv = await readFileContainer(id, "/tmp/kirocrew-gateway-env");
    expect(gatewayEnv).toContain(`KIROCREW_PORT=${gatewayPort}`);
    expect(gatewayEnv).toContain(
      `KIROCREW_CORS_ORIGINS=${dashboardOrigin},https://extra.example.com`,
    );
    expect(gatewayEnv).toContain("KIRO_AWS_BUILDER_ID_TOKEN=builder-token");

    const calls = await readFileContainer(id, "/tmp/kirocrew-calls");
    expect(calls).toContain(`config set dashboard.url ${dashboardOrigin}`);

    for (const file of ["start.log", "gateway.log", "redirector.log"]) {
      const exists = await execContainer(id, [
        "test",
        "-f",
        `${moduleLogDir}/${file}`,
      ]);
      expect(exists.exitCode).toBe(0);
    }
  });

  test("redirector-returns-503-until-gateway-ready", async () => {
    const { id, scripts } = await setup({ withMocks: true });
    await runOrFail(id, "install", scripts.install);
    await runOrFail(id, "start", scripts.start, {
      KIROCREW_MOCK_GATEWAY: "hang",
    });
    await waitForStatus(id, `http://127.0.0.1:${redirectPort}/healthz`, "200");
    const resp = await waitForStatus(
      id,
      `http://127.0.0.1:${redirectPort}/`,
      "503",
    );
    expect(resp).toStartWith("503");
  });

  test("start-replaces-stale-listener-on-gateway-port", async () => {
    const { id, scripts } = await setup({ withMocks: true });
    await runOrFail(id, "install", scripts.install);
    await execContainer(id, [
      "bash",
      "-c",
      `setsid nohup python3 -m http.server --bind 127.0.0.1 ${gatewayPort} > /dev/null 2>&1 < /dev/null &`,
    ]);
    await waitForStatus(id, `http://127.0.0.1:${gatewayPort}/`, "200");
    await runOrFail(id, "start", scripts.start);
    await waitForStatus(id, `http://127.0.0.1:${gatewayPort}/health`, "200");
    const health = await execContainer(id, [
      "/usr/bin/curl",
      "-s",
      `http://127.0.0.1:${gatewayPort}/health`,
    ]);
    expect(health.stdout).toBe("fake-gateway");
  });

  test("start-fails-without-kirocrew", async () => {
    const { id, scripts } = await setup();
    // The install wrapper normally creates the module directories.
    await execContainer(id, [
      "mkdir",
      "-p",
      "/home/coder/.coder-modules/coder-labs/kiro-crew/scripts",
      moduleLogDir,
    ]);
    const resp = await runScript(id, "start", scripts.start);
    expect(resp.exitCode).not.toBe(0);
    const log = await readFileContainer(id, `${moduleLogDir}/start.log`);
    expect(log).toContain("kirocrew binary not found");
  });
});
