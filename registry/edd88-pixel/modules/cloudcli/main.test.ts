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
  testRequiredVariables,
  writeCoder,
  writeFileContainer,
} from "~test";
import path from "node:path";

const MODULE_ROOT = "/home/coder/.coder-modules/edd88-pixel/cloudcli";
const DEFAULT_PATH =
  "/usr/local/test-bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";

interface ModuleScripts {
  install: string;
  start: string;
}

interface SetupResult {
  id: string;
  scripts: ModuleScripts;
}

let defaultScripts: ModuleScripts;
let customScripts: ModuleScripts;
let cleanupFunctions: Array<() => Promise<void>> = [];

const collectScripts = (state: TerraformState): ModuleScripts => {
  const scripts: Partial<ModuleScripts> = {};

  for (const resource of state.resources) {
    if (resource.type !== "coder_script") {
      continue;
    }

    for (const instance of resource.instances) {
      const attributes = instance.attributes as Record<string, unknown>;
      const displayName = attributes.display_name;
      const script = attributes.script;
      if (typeof displayName !== "string" || typeof script !== "string") {
        continue;
      }

      if (displayName === "CloudCLI: Install Script") {
        scripts.install = script;
      } else if (displayName === "CloudCLI: Start Script") {
        scripts.start = script;
      }
    }
  }

  if (!scripts.install || !scripts.start) {
    throw new Error("CloudCLI install and start scripts were not found");
  }

  return scripts as ModuleScripts;
};

const npmMock = `#!/usr/bin/env bash
set -euo pipefail

if [ "\${1:-}" = "--version" ]; then
  printf '10.0.0\\n'
  exit 0
fi

if [ "\${1:-}" != "install" ]; then
  printf 'unexpected npm command: %s\\n' "$*" >&2
  exit 2
fi

printf '%s\\n' "$*" > /tmp/npm-invocation
prefix=""
package_spec=""
shift

while [ "$#" -gt 0 ]; do
  case "$1" in
    --prefix)
      prefix="$2"
      shift 2
      ;;
    @cloudcli-ai/cloudcli@*)
      package_spec="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

if [ -z "$prefix" ] || [ -z "$package_spec" ]; then
  printf 'missing npm prefix or CloudCLI package spec\\n' >&2
  exit 2
fi

version="\${package_spec##*@}"
package_dir="$prefix/node_modules/@cloudcli-ai/cloudcli"
mkdir -p "$package_dir" "$prefix/node_modules/.bin"
printf '{"name":"@cloudcli-ai/cloudcli","version":"%s"}\\n' "$version" > "$package_dir/package.json"
cp /tmp/cloudcli-mock.sh "$prefix/node_modules/.bin/cloudcli"
chmod 755 "$prefix/node_modules/.bin/cloudcli"
`;

const runScript = async (
  id: string,
  name: string,
  script: string,
  pathValue = DEFAULT_PATH,
) => {
  const scriptPath = `/tmp/${name}.sh`;
  await writeFileContainer(id, scriptPath, script, { user: "root" });
  const chmod = await execContainer(
    id,
    ["chmod", "755", scriptPath],
    ["--user", "root"],
  );
  expect(chmod.exitCode).toBe(0);

  return execContainer(
    id,
    ["bash", scriptPath],
    [
      "--user",
      "coder",
      "--env",
      "HOME=/home/coder",
      "--env",
      `PATH=${pathValue}`,
    ],
  );
};

const setup = async (scripts = defaultScripts): Promise<SetupResult> => {
  const id = await runContainer("node:22-bookworm-slim");
  cleanupFunctions.push(async () => {
    await removeContainer(id);
  });

  const createUser = await execContainer(
    id,
    [
      "bash",
      "-c",
      "id coder >/dev/null 2>&1 || useradd --create-home --shell /bin/bash coder",
    ],
    ["--user", "root"],
  );
  expect(createUser.exitCode).toBe(0);

  await writeCoder(id, "#!/usr/bin/env bash\nexit 0\n");
  await writeFileContainer(
    id,
    "/tmp/cloudcli-mock.sh",
    await Bun.file(
      path.join(import.meta.dir, "testdata", "cloudcli-mock.sh"),
    ).text(),
    { user: "root" },
  );
  await writeFileContainer(id, "/tmp/npm-mock.sh", npmMock, {
    user: "root",
  });

  const installMocks = await execContainer(
    id,
    [
      "bash",
      "-c",
      "mkdir -p /usr/local/test-bin && cp /tmp/npm-mock.sh /usr/local/test-bin/npm && chmod 755 /usr/local/test-bin/npm /tmp/cloudcli-mock.sh",
    ],
    ["--user", "root"],
  );
  expect(installMocks.exitCode).toBe(0);

  return { id, scripts };
};

const installCloudCLI = async (result: SetupResult) => {
  const response = await runScript(
    result.id,
    "cloudcli-install",
    result.scripts.install,
  );
  if (response.exitCode !== 0) {
    console.error(response.stdout);
    console.error(response.stderr);
  }
  expect(response.exitCode).toBe(0);
};

const startCloudCLI = async (result: SetupResult) => {
  const response = await runScript(
    result.id,
    "cloudcli-start",
    result.scripts.start,
  );
  if (response.exitCode !== 0) {
    console.error(response.stdout);
    console.error(response.stderr);
  }
  expect(response.exitCode).toBe(0);
  return response;
};

afterEach(async () => {
  const cleanups = cleanupFunctions.reverse();
  cleanupFunctions = [];

  for (const cleanup of cleanups) {
    try {
      await cleanup();
    } catch (error) {
      console.error("Container cleanup failed:", error);
    }
  }
});

setDefaultTimeout(120_000);

describe("cloudcli", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
    defaultScripts = collectScripts(
      await runTerraformApply(import.meta.dir, {
        agent_id: "test-agent",
      }),
    );
    customScripts = collectScripts(
      await runTerraformApply(import.meta.dir, {
        agent_id: "test-agent",
        port: 43123,
        workspaces_root: "/home/coder/project",
      }),
    );
  });

  testRequiredVariables(import.meta.dir, {
    agent_id: "test-agent",
  });

  test("installs the exact package version in the isolated runtime", async () => {
    const result = await setup();
    await installCloudCLI(result);

    const packageJSON = await readFileContainer(
      result.id,
      `${MODULE_ROOT}/runtime/node_modules/@cloudcli-ai/cloudcli/package.json`,
    );
    expect(JSON.parse(packageJSON).version).toBe("1.35.0");

    const invocation = await readFileContainer(
      result.id,
      "/tmp/npm-invocation",
    );
    expect(invocation).toContain(`--prefix ${MODULE_ROOT}/runtime`);
    expect(invocation).toContain("@cloudcli-ai/cloudcli@1.35.0");
    expect(invocation).not.toMatch(/(^|\s)(-g|--global)(\s|$)/);

    const globalBinary = await execContainer(
      result.id,
      ["bash", "-c", "command -v cloudcli"],
      [
        "--user",
        "coder",
        "--env",
        "HOME=/home/coder",
        "--env",
        `PATH=${DEFAULT_PATH}`,
      ],
    );
    expect(globalBinary.exitCode).not.toBe(0);
  });

  test("starts on IPv4 loopback with the secure defaults", async () => {
    const result = await setup();
    await installCloudCLI(result);

    await execContainer(
      result.id,
      [
        "bash",
        "-c",
        `mkdir -p '${MODULE_ROOT}/run' && echo 999999 > '${MODULE_ROOT}/run/cloudcli.pid' && chown -R coder:coder '/home/coder/.coder-modules'`,
      ],
      ["--user", "root"],
    );
    const response = await startCloudCLI(result);
    expect(response.stdout).toContain("Waiting for CloudCLI to come online...");
    expect(response.stderr).not.toContain("curl:");

    const health = await execContainer(
      result.id,
      [
        "node",
        "-e",
        "require('node:http').get('http://127.0.0.1:3001/health',r=>{r.resume();process.exit(r.statusCode===200?0:1)}).on('error',()=>process.exit(1))",
      ],
      ["--user", "coder"],
    );
    expect(health.exitCode).toBe(0);

    const listener = await execContainer(result.id, [
      "bash",
      "-c",
      "port_hex=$(printf '%04X' 3001); awk -v expected=\"0100007F:$port_hex\" '$2 == expected && $4 == \"0A\" { print $2 }' /proc/net/tcp",
    ]);
    expect(listener.stdout.trim()).toBe("0100007F:0BB9");

    const environment = await readFileContainer(
      result.id,
      `${MODULE_ROOT}/run/mock-environment`,
    );
    expect(environment).toContain("HOST=127.0.0.1");
    expect(environment).toContain("SERVER_PORT=3001");
    expect(environment).toContain(`DATABASE_PATH=${MODULE_ROOT}/data/auth.db`);
    expect(environment).toContain("WORKSPACES_ROOT=\n");

    const pid = await readFileContainer(
      result.id,
      `${MODULE_ROOT}/run/cloudcli.pid`,
    );
    expect(pid.trim()).not.toBe("999999");
  });

  test("renders a custom port and workspace root safely", async () => {
    const result = await setup(customScripts);
    await installCloudCLI(result);
    await startCloudCLI(result);

    const environment = await readFileContainer(
      result.id,
      `${MODULE_ROOT}/run/mock-environment`,
    );
    expect(environment).toContain("HOST=127.0.0.1");
    expect(environment).toContain("SERVER_PORT=43123");
    expect(environment).toContain("WORKSPACES_ROOT=/home/coder/project");

    const argumentsFile = await readFileContainer(
      result.id,
      `${MODULE_ROOT}/run/mock-arguments`,
    );
    expect(argumentsFile).toContain("--port 43123");
    expect(argumentsFile).toContain(
      `--database-path ${MODULE_ROOT}/data/auth.db`,
    );
  });

  test("does not start a second process when CloudCLI is healthy", async () => {
    const result = await setup();
    await installCloudCLI(result);
    await startCloudCLI(result);

    const firstPID = (
      await readFileContainer(result.id, `${MODULE_ROOT}/run/cloudcli.pid`)
    ).trim();
    await startCloudCLI(result);
    const secondPID = (
      await readFileContainer(result.id, `${MODULE_ROOT}/run/cloudcli.pid`)
    ).trim();

    expect(secondPID).toBe(firstPID);
  });

  test("fails without terminating an unrelated listener", async () => {
    const result = await setup();
    await installCloudCLI(result);

    const occupied = await execContainer(
      result.id,
      [
        "bash",
        "-c",
        "nohup node -e \"require('node:http').createServer((q,s)=>{s.statusCode=404;s.end()}).listen(3001,'127.0.0.1')\" >/tmp/occupied.log 2>&1 & echo $! >/tmp/occupied.pid; sleep 1",
      ],
      ["--user", "coder", "--env", "HOME=/home/coder"],
    );
    expect(occupied.exitCode).toBe(0);

    const response = await runScript(
      result.id,
      "cloudcli-start-occupied",
      result.scripts.start,
    );
    expect(response.exitCode).not.toBe(0);
    expect(`${response.stdout}\n${response.stderr}`).toContain(
      "already used by another process",
    );

    const stillRunning = await execContainer(
      result.id,
      ["bash", "-c", 'kill -0 "$(cat /tmp/occupied.pid)"'],
      ["--user", "coder"],
    );
    expect(stillRunning.exitCode).toBe(0);
  });

  test("rejects a healthy listener that is not restricted to loopback", async () => {
    const result = await setup();
    await installCloudCLI(result);

    const occupied = await execContainer(
      result.id,
      [
        "bash",
        "-c",
        "nohup node -e \"require('node:http').createServer((q,s)=>{s.setHeader('content-type','application/json');s.end(JSON.stringify({status:'ok'}))}).listen(3001,'0.0.0.0')\" >/tmp/wildcard.log 2>&1 & echo $! >/tmp/wildcard.pid; sleep 1",
      ],
      ["--user", "coder", "--env", "HOME=/home/coder"],
    );
    expect(occupied.exitCode).toBe(0);

    const response = await runScript(
      result.id,
      "cloudcli-start-wildcard",
      result.scripts.start,
    );
    expect(response.exitCode).not.toBe(0);
    expect(`${response.stdout}\n${response.stderr}`).toContain(
      "not restricted to IPv4 loopback",
    );

    const stillRunning = await execContainer(
      result.id,
      ["bash", "-c", 'kill -0 "$(cat /tmp/wildcard.pid)"'],
      ["--user", "coder"],
    );
    expect(stillRunning.exitCode).toBe(0);
  });

  test("rejects a workspace without Node.js", async () => {
    const result = await setup();
    const response = await runScript(
      result.id,
      "cloudcli-install-no-node",
      result.scripts.install,
      "/usr/local/test-bin:/usr/bin:/bin",
    );

    expect(response.exitCode).not.toBe(0);
    expect(`${response.stdout}\n${response.stderr}`).toContain(
      "node is required",
    );
  });

  test("rejects Node.js versions older than 22", async () => {
    const result = await setup();
    await writeFileContainer(
      result.id,
      "/tmp/node",
      "#!/usr/bin/env bash\nprintf 'v20.19.0\\n'\n",
      { user: "root" },
    );
    const prepareOldNode = await execContainer(
      result.id,
      [
        "bash",
        "-c",
        "mkdir -p /tmp/old-node-bin && cp /tmp/node /tmp/old-node-bin/node && chmod 755 /tmp/old-node-bin/node",
      ],
      ["--user", "root"],
    );
    expect(prepareOldNode.exitCode).toBe(0);

    const response = await runScript(
      result.id,
      "cloudcli-install-old-node",
      result.scripts.install,
      "/tmp/old-node-bin:/usr/local/test-bin:/usr/bin:/bin",
    );

    expect(response.exitCode).not.toBe(0);
    expect(`${response.stdout}\n${response.stderr}`).toContain(
      "requires Node.js 22 or newer; found v20.19.0",
    );
  });
});
