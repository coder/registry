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
const moduleDataDir = "/home/coder/.coder-modules/coder-labs/kiro-crew";
const moduleLogDir = `${moduleDataDir}/logs`;
const moduleScriptsDir = `${moduleDataDir}/scripts`;

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
echo "kiro-crew installer ran PYTHONPATH=\${PYTHONPATH-unset}" >> /tmp/installers-ran
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
};

// Polls a URL from inside the container until curl reports the expected
// status code, then prints "<status> <redirect_url>". A host sets the Host
// header, as Coder's app proxy forwards the browser's Host.
const waitForStatus = async (
  id: string,
  url: string,
  status: string,
  host?: string,
) => {
  const hostHeader = host ? `-H 'Host: ${host}'` : "";
  const resp = await execContainer(id, [
    "bash",
    "-c",
    `for i in $(seq 1 100); do
       out=$(/usr/bin/curl -s -o /dev/null ${hostHeader} -w '%{http_code} %{redirect_url}' '${url}')
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

// Names the coder provider resolved for the workspace and owner, which shape
// every app hostname.
const workspaceNames = (state: TerraformState) => {
  const nameOf = (type: string) => {
    const resource = state.resources.find((r) => r.type === type);
    const name = resource?.instances[0]?.attributes.name;
    if (typeof name !== "string" || name === "") {
      throw new Error(`${type} name not found in terraform state`);
    }
    return name;
  };
  return {
    workspace: nameOf("coder_workspace"),
    owner: nameOf("coder_workspace_owner"),
  };
};

const agentName = "main";

// What the agent sets for a deployment whose wildcard is *--apps.coder.example.com.
const proxyURIEnv = (state: TerraformState) => {
  const { workspace, owner } = workspaceNames(state);
  return {
    CODER_WORKSPACE_AGENT_NAME: agentName,
    VSCODE_PROXY_URI: `https://{{port}}--${agentName}--${workspace}--${owner}--apps.coder.example.com`,
  };
};

const gatewayOrigins = async (id: string) => {
  const env = await readFileContainer(id, "/tmp/kirocrew-gateway-env");
  const line = env
    .split("\n")
    .find((l) => l.startsWith("KIROCREW_CORS_ORIGINS="));
  return (line ?? "").replace("KIROCREW_CORS_ORIGINS=", "").split(",");
};

// Requests the redirector with the given Host and returns the redirect
// origin, asserting the gateway trusts it.
const redirectOrigin = async (id: string, host: string) => {
  const out = await waitForStatus(
    id,
    `http://127.0.0.1:${redirectPort}/`,
    "302",
    host,
  );
  const location = out.replace(/^302 /, "");
  expect(location).toEndWith("/?token=test-token");
  const origin = location.replace("/?token=test-token", "");
  expect(await gatewayOrigins(id)).toContain(origin);
  return origin;
};

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
    expect(ran).toContain("kiro-crew installer ran PYTHONPATH=unset");
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
    const { workspace, owner } = workspaceNames(state);
    const dashboardOrigin = `https://kirocrew-dashboard--${workspace}--${owner}--apps.coder.example.com`;
    await runOrFail(id, "install", scripts.install);
    await execContainer(id, [
      "bash",
      "-c",
      "mkdir -p ~/.kiro/crew && touch ~/.kiro/crew/start-gateway.sh ~/.kiro/crew/redirect-gateway.py",
    ]);
    const start = await runOrFail(id, "start", scripts.start, {
      KIRO_AWS_BUILDER_ID_TOKEN: "builder-token",
      ...proxyURIEnv(state),
    });
    expect(start.stdout).toContain("Kiro Crew gateway launch dispatched.");
    expect(start.stdout).toContain(
      `Primary dashboard origin: ${dashboardOrigin}`,
    );

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
      `KIROCREW_CORS_ORIGINS=${dashboardOrigin},https://kirocrew-dashboard--${agentName}--${workspace}--${owner}--apps.coder.example.com,https://extra.example.com`,
    );
    expect(gatewayEnv).toContain("KIRO_AWS_BUILDER_ID_TOKEN=builder-token");

    const calls = await readFileContainer(id, "/tmp/kirocrew-calls");
    expect(calls).toContain(`config set dashboard.url ${dashboardOrigin}`);

    for (const file of [
      `${moduleLogDir}/start.log`,
      `${moduleLogDir}/gateway.log`,
      `${moduleLogDir}/redirector.log`,
      `${moduleScriptsDir}/start-gateway.sh`,
      `${moduleScriptsDir}/redirect-gateway.py`,
      `${moduleScriptsDir}/coder-origins.py`,
      `${moduleDataDir}/coder-origins.json`,
    ]) {
      const exists = await execContainer(id, ["test", "-f", file]);
      expect(exists.exitCode).toBe(0);
    }
    const legacy = await execContainer(id, [
      "bash",
      "-c",
      "ls ~/.kiro/crew/start-gateway.sh ~/.kiro/crew/redirect-gateway.py",
    ]);
    expect(legacy.exitCode).not.toBe(0);
  });

  test("redirector-keeps-browser-on-its-workspace-proxy", async () => {
    const { id, scripts, state } = await setup({
      withMocks: true,
      moduleVariables: {
        workspace_proxy_hostnames: JSON.stringify([
          "*--apps.eu.coder.example.com",
          "http://*.apps.lab.example.com:8080",
        ]),
      },
    });
    const { workspace, owner } = workspaceNames(state);
    const sub = `${workspace}--${owner}`;
    await runOrFail(id, "install", scripts.install);
    await runOrFail(id, "start", scripts.start, proxyURIEnv(state));

    // Primary deployment.
    expect(
      await redirectOrigin(id, `kirocrew--${sub}--apps.coder.example.com`),
    ).toBe(`https://kirocrew-dashboard--${sub}--apps.coder.example.com`);
    // Listed proxy, in the form Coder links to and in the form naming the agent.
    expect(
      await redirectOrigin(id, `kirocrew--${sub}--apps.eu.coder.example.com`),
    ).toBe(`https://kirocrew-dashboard--${sub}--apps.eu.coder.example.com`);
    expect(
      await redirectOrigin(
        id,
        `KIROCREW--${agentName}--${sub}--apps.eu.coder.example.com`,
      ),
    ).toBe(
      `https://kirocrew-dashboard--${agentName}--${sub}--apps.eu.coder.example.com`,
    );
    // Explicit scheme and port.
    expect(
      await redirectOrigin(id, `kirocrew--${sub}.apps.lab.example.com:8080`),
    ).toBe(`http://kirocrew-dashboard--${sub}.apps.lab.example.com:8080`);
    // Unlisted proxies and unrelated hosts fall back to the primary origin.
    for (const host of [
      `kirocrew--${sub}--apps.ap.coder.example.com`,
      `kirocrew--${sub}--apps.attacker.example`,
    ]) {
      expect(await redirectOrigin(id, host)).toBe(
        `https://kirocrew-dashboard--${sub}--apps.coder.example.com`,
      );
    }
  });

  test("dashboard-origin-override-is-the-primary-origin", async () => {
    const override = "https://crew.apps.example.com";
    const { id, scripts, state } = await setup({
      withMocks: true,
      moduleVariables: { dashboard_origin: override },
    });
    const { workspace, owner } = workspaceNames(state);
    await runOrFail(id, "install", scripts.install);
    await runOrFail(id, "start", scripts.start, proxyURIEnv(state));
    expect(
      await redirectOrigin(
        id,
        `kirocrew--${workspace}--${owner}--apps.coder.example.com`,
      ),
    ).toBe(override);
    expect(await gatewayOrigins(id)).toEqual([override]);
    const calls = await readFileContainer(id, "/tmp/kirocrew-calls");
    expect(calls).toContain(`config set dashboard.url ${override}`);
  });

  test("start-falls-back-without-vscode-proxy-uri", async () => {
    const { id, scripts, state } = await setup({ withMocks: true });
    const fallback = state.outputs.dashboard_origin.value as string;
    await runOrFail(id, "install", scripts.install);
    const start = await runOrFail(id, "start", scripts.start);
    expect(start.stdout + start.stderr).toContain(
      "WARNING: could not determine the wildcard app hostname",
    );
    expect(await redirectOrigin(id, "127.0.0.1")).toBe(fallback);
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
