import {
  afterEach,
  beforeAll,
  describe,
  expect,
  setDefaultTimeout,
  test,
} from "bun:test";
import path from "path";
import {
  execContainer,
  readFileContainer,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  type TerraformState,
} from "~test";
import { writeExecutable } from "../../../coder/modules/agentapi/test-util";

const moduleDir = path.resolve(import.meta.dir);
const home = "/home/coder";
const passwordFile = `${home}/.config/opencode/server-password`;
const configFile = `${home}/.config/opencode/opencode.json`;

// coder_env.opencode uses for_each, so collect every instance.
const envVars = (state: TerraformState): Record<string, string> => {
  const vars: Record<string, string> = {};
  for (const resource of state.resources) {
    if (resource.type !== "coder_env") continue;
    for (const instance of resource.instances) {
      const attrs = instance.attributes as Record<string, unknown>;
      vars[attrs.name as string] = attrs.value as string;
    }
  }
  return vars;
};

const scriptByName = (state: TerraformState, suffix: string): string => {
  for (const resource of state.resources) {
    if (resource.type !== "coder_script") continue;
    for (const instance of resource.instances) {
      const attrs = instance.attributes as Record<string, unknown>;
      if (attrs.display_name === `OpenCode server: ${suffix}`) {
        return attrs.script as string;
      }
    }
  }
  throw new Error(`coder_script "${suffix}" not found`);
};

let cleanups: (() => Promise<void>)[] = [];
afterEach(async () => {
  const pending = cleanups.reverse();
  cleanups = [];
  for (const cleanup of pending) {
    await cleanup().catch((err) => console.error("cleanup failed:", err));
  }
});

const setup = async (
  vars: Record<string, string> = {},
  opts: { mockOpencode?: boolean } = {},
) => {
  const state = await runTerraformApply(moduleDir, {
    agent_id: "foo",
    install_opencode: "false",
    ...vars,
  });
  const id = await runContainer("codercom/enterprise-node:latest");
  cleanups.push(() => removeContainer(id));

  // coder-utils calls `coder exp sync`; a no-op stub is enough here.
  await writeExecutable({
    containerId: id,
    filePath: "/usr/bin/coder",
    content: "#!/bin/bash\nexit 0\n",
  });
  const mock = await Bun.file(
    path.join(moduleDir, "testdata", "opencode-mock.sh"),
  ).text();
  if (opts.mockOpencode ?? true) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/opencode",
      content: mock,
    });
  }
  return {
    id,
    mock,
    env: envVars(state),
    install: scriptByName(state, "Install Script"),
    start: scriptByName(state, "Start Script"),
  };
};

const run = async (
  id: string,
  name: string,
  script: string,
  env: Record<string, string> = {},
) => {
  const target = `/tmp/${name}.sh`;
  await writeExecutable({ containerId: id, filePath: target, content: script });
  const exports = Object.entries(env)
    .map(([k, v]) => `export ${k}='${v}'; `)
    .join("");
  return execContainer(id, ["bash", "-c", `${exports}${target}`]);
};

const health = (id: string, password: string) =>
  execContainer(id, [
    "curl",
    "-s",
    "-o",
    "/dev/null",
    "-w",
    "%{http_code}",
    "-u",
    `opencode:${password}`,
    "http://127.0.0.1:4096/global/health",
  ]);

setDefaultTimeout(90 * 1000);

describe("opencode-server", () => {
  beforeAll(async () => {
    await runTerraformInit(moduleDir);
  });

  test("installs, starts and protects the server", async () => {
    const { id, install, start } = await setup();

    const installed = await run(id, "install", install);
    expect(installed.exitCode).toBe(0);
    expect(
      (
        await execContainer(id, ["stat", "-c", "%a", passwordFile])
      ).stdout.trim(),
    ).toBe("600");

    const started = await run(id, "start", start);
    expect(started.exitCode).toBe(0);
    expect(started.stdout).toContain("OpenCode server is up.");

    const password = (await readFileContainer(id, passwordFile)).trim();
    expect((await health(id, password)).stdout).toBe("200");
    expect((await health(id, "wrong")).stdout).toBe("401");

    // A second start (agent restart) must reuse the running server.
    const restarted = await run(id, "start", start);
    expect(restarted.exitCode).toBe(0);
    expect(restarted.stdout).toContain("already running");
    const calls = await readFileContainer(id, "/tmp/opencode-mock-calls");
    expect(calls.trim().split("\n")).toHaveLength(1);
  });

  test("keeps an existing password and opencode.json", async () => {
    const { id, install } = await setup({ enable_ai_gateway: "true" });
    await execContainer(id, [
      "bash",
      "-c",
      `mkdir -p ${home}/.config/opencode && echo keep-me > ${passwordFile} && echo '{"theme":"mine"}' > ${configFile}`,
    ]);

    expect((await run(id, "install", install)).exitCode).toBe(0);
    expect((await readFileContainer(id, passwordFile)).trim()).toBe("keep-me");
    expect(await readFileContainer(id, configFile)).toContain('"theme":"mine"');
  });

  test("writes AI Gateway config without the token", async () => {
    const { id, install, env } = await setup({ enable_ai_gateway: "true" });
    expect(env.OPENCODE_SERVER_AI_GATEWAY_URL).toEndWith("/api/v2/ai-gateway");

    expect((await run(id, "install", install)).exitCode).toBe(0);
    const config = await readFileContainer(id, configFile);
    expect(config).toContain(
      "{env:OPENCODE_SERVER_AI_GATEWAY_URL}/anthropic/v1",
    );
    expect(config).toContain("{env:OPENCODE_SERVER_AI_GATEWAY_TOKEN}");
  });

  test("config_json overwrites opencode.json", async () => {
    const { id, install } = await setup({
      config_json: JSON.stringify({ autoupdate: false }),
    });
    await execContainer(id, [
      "bash",
      "-c",
      `mkdir -p ${home}/.config/opencode && echo '{"old":true}' > ${configFile}`,
    ]);

    expect((await run(id, "install", install)).exitCode).toBe(0);
    expect(JSON.parse(await readFileContainer(id, configFile))).toEqual({
      autoupdate: false,
    });
  });

  test("rejects OpenCode 2", async () => {
    const { id, install } = await setup();
    const result = await run(id, "install", install, {
      MOCK_OPENCODE_VERSION: "2.0.27",
    });
    expect(result.exitCode).not.toBe(0);
    expect(result.stdout + result.stderr).toContain(
      "supports OpenCode 1.x only",
    );
  });

  test("installs from binary_url archives", async () => {
    const { id, install, mock } = await setup(
      {
        install_opencode: "true",
        binary_url: "file:///tmp/mirror/opencode-linux-{arch}.tar.gz",
      },
      { mockOpencode: false },
    );
    await execContainer(id, ["mkdir", "-p", "/tmp/staging"]);
    await writeExecutable({
      containerId: id,
      filePath: "/tmp/staging/opencode",
      content: mock,
    });
    await execContainer(id, [
      "bash",
      "-c",
      'arch=$(uname -m); case $arch in x86_64) arch=x64;; aarch64) arch=arm64;; esac; mkdir -p /tmp/mirror && tar -czf "/tmp/mirror/opencode-linux-$arch.tar.gz" -C /tmp/staging opencode',
    ]);

    const result = await run(id, "install", install);
    expect(result.exitCode).toBe(0);
    expect(
      (
        await execContainer(id, [`${home}/.opencode/bin/opencode`, "--version"])
      ).stdout.trim(),
    ).toBe("1.19.5");
  });

  test("offline sets the OpenCode network switches", async () => {
    const { env: defaults } = await setup();
    expect(defaults.OPENCODE_DISABLE_AUTOUPDATE).toBe("true");
    expect(defaults.OPENCODE_DISABLE_MODELS_FETCH).toBeUndefined();

    const { env } = await setup({ offline: "true" });
    for (const name of [
      "OPENCODE_DISABLE_AUTOUPDATE",
      "OPENCODE_DISABLE_MODELS_FETCH",
      "OPENCODE_DISABLE_DEFAULT_PLUGINS",
      "OPENCODE_DISABLE_LSP_DOWNLOAD",
    ]) {
      expect(env[name]).toBe("true");
    }
  });

  test("starts the server through the Agent Firewall wrapper", async () => {
    const wrapper = "/tmp/fw/wrapper.sh";
    const { id, install, start } = await setup({
      agent_firewall_wrapper_path: wrapper,
      agent_firewall_config_path: "/tmp/fw/config.yaml",
    });
    await execContainer(id, ["mkdir", "-p", "/tmp/fw"]);
    // Records its arguments, then runs the wrapped command like the real one.
    await writeExecutable({
      containerId: id,
      filePath: wrapper,
      content:
        '#!/bin/bash\necho "$@" > /tmp/fw/args\nwhile [ "$1" != "--" ]; do shift; done\nshift\nexec "$@"\n',
    });
    await execContainer(id, ["bash", "-c", "touch /tmp/fw/config.yaml"]);

    expect((await run(id, "install", install)).exitCode).toBe(0);
    const started = await run(id, "start", start);
    expect(started.exitCode).toBe(0);
    expect(started.stdout).toContain("inside Agent Firewall");
    expect(await readFileContainer(id, "/tmp/fw/args")).toContain(
      "--jail-type=landjail --config=/tmp/fw/config.yaml -- opencode serve",
    );
  });
});
