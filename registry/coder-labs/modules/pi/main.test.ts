import {
  test,
  afterEach,
  describe,
  setDefaultTimeout,
  beforeAll,
  expect,
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
import {
  extractCoderEnvVars,
  writeExecutable,
} from "../../../coder/modules/agentapi/test-util";
import path from "path";

interface ModuleScripts {
  pre_install?: string;
  install: string;
  post_install?: string;
}

const SCRIPT_SUFFIXES = [
  "Pre-Install Script",
  "Install Script",
  "Post-Install Script",
] as const;

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
  const scripts: Partial<ModuleScripts> = {};
  for (const suffix of SCRIPT_SUFFIXES) {
    const key = `Pi: ${suffix}`;
    if (!(key in byDisplayName)) continue;
    switch (suffix) {
      case "Pre-Install Script":
        scripts.pre_install = byDisplayName[key];
        break;
      case "Install Script":
        scripts.install = byDisplayName[key];
        break;
      case "Post-Install Script":
        scripts.post_install = byDisplayName[key];
        break;
    }
  }
  if (!scripts.install) {
    throw new Error("install script not found in terraform state");
  }
  return scripts as ModuleScripts;
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

interface SetupProps {
  skipPiMock?: boolean;
  moduleVariables?: Record<string, string>;
}

const setup = async (
  props?: SetupProps,
): Promise<{
  id: string;
  coderEnvVars: Record<string, string>;
  scripts: ModuleScripts;
}> => {
  const projectDir = "/home/coder/project";
  const moduleDir = path.resolve(import.meta.dir);
  const state = await runTerraformApply(moduleDir, {
    agent_id: "foo",
    workdir: projectDir,
    install_pi: "false",
    ...props?.moduleVariables,
  });
  const scripts = collectScripts(state);
  const coderEnvVars = extractCoderEnvVars(state);

  const id = await runContainer("codercom/enterprise-node:latest");
  registerCleanup(async () => {
    if (process.env["DEBUG"] === "true" || process.env["DEBUG"] === "1") {
      console.log(`Not removing container ${id} in debug mode`);
      return;
    }
    await removeContainer(id);
  });

  await execContainer(id, ["bash", "-c", `mkdir -p '${projectDir}'`]);
  await writeExecutable({
    containerId: id,
    filePath: "/usr/bin/coder",
    content: "#!/bin/bash\nexit 0\n",
  });
  if (!props?.skipPiMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/pi",
      content: await Bun.file(
        path.join(moduleDir, "testdata", "pi-mock.sh"),
      ).text(),
    });
  }
  return { id, coderEnvVars, scripts };
};

const runScripts = async (
  id: string,
  scripts: ModuleScripts,
  env?: Record<string, string>,
) => {
  const entries = env ? Object.entries(env) : [];
  const envArgs =
    entries.length > 0
      ? entries
          .map(
            ([key, value]) => `export ${key}="${value.replace(/"/g, '\\"')}"`,
          )
          .join(" && ") + " && "
      : "";
  const runRenderedScript = async (name: string, script: string) => {
    const target = `/tmp/coder-utils-${name}.sh`;
    await writeExecutable({
      containerId: id,
      filePath: target,
      content: script,
    });
    return execContainer(id, ["bash", "-c", `${envArgs}${target}`]);
  };
  const ordered: [string, string | undefined][] = [
    ["pre_install", scripts.pre_install],
    ["install", scripts.install],
    ["post_install", scripts.post_install],
  ];
  for (const [name, script] of ordered) {
    if (!script) continue;
    const resp = await runRenderedScript(name, script);
    if (resp.exitCode !== 0) {
      console.log(`script ${name} failed:`);
      console.log(resp.stdout);
      console.log(resp.stderr);
      throw new Error(`coder-utils ${name} script exited ${resp.exitCode}`);
    }
  }
};

const runInstallScript = async (
  id: string,
  script: string,
  env?: Record<string, string>,
) => {
  const entries = env ? Object.entries(env) : [];
  const envArgs = entries
    .map(([key, value]) => `export ${key}="${value.replace(/"/g, '\\"')}"`)
    .join(" && ");
  const target = "/tmp/coder-utils-install.sh";
  await writeExecutable({ containerId: id, filePath: target, content: script });
  return execContainer(id, [
    "bash",
    "-c",
    `${envArgs ? `${envArgs} && ` : ""}${target}`,
  ]);
};

const installLog = (id: string) =>
  readFileContainer(
    id,
    "/home/coder/.coder-modules/coder-labs/pi/logs/install.log",
  );

setDefaultTimeout(60 * 1000);

describe("pi", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const log = await installLog(id);
    expect(log).toContain("Skipping Pi installation");
  });

  test("preinstalled-pi-is-required-when-installation-is-disabled", async () => {
    const { id, scripts } = await setup({ skipPiMock: true });
    const result = await runInstallScript(id, scripts.install);
    expect(result.exitCode).not.toBe(0);
    const log = await installLog(id);
    expect(log).toContain("Pi binary was not found or is not executable.");
  });

  test("install-requires-npm", async () => {
    const { id, scripts } = await setup({
      skipPiMock: true,
      moduleVariables: { install_pi: "true" },
    });
    // npm and its supporting files are root-owned on
    // codercom/enterprise-node:latest, so removing it as the workspace user
    // (as a plain `mv` would attempt) fails silently and leaves npm in
    // place. Remove it as root to actually simulate npm being absent.
    await execContainer(
      id,
      ["bash", "-c", "rm -f $(command -v npm) $(command -v npx)"],
      ["-u", "root"],
    );
    const result = await runInstallScript(id, scripts.install);
    expect(result.exitCode).not.toBe(0);
    const log = await installLog(id);
    expect(log).toContain("npm was not found");
  });

  test("install-does-not-require-writable-global-npm-prefix", async () => {
    // codercom/enterprise-node:latest sets npm's default global prefix to
    // /usr, which is root-owned. A plain `npm install -g` fails with EACCES
    // for the unprivileged "coder" user; the module must install into a
    // prefix it owns instead.
    const { id, scripts } = await setup({
      skipPiMock: true,
      moduleVariables: { install_pi: "true" },
    });
    const result = await runInstallScript(id, scripts.install);
    expect(result.exitCode).toBe(0);
    const log = await installLog(id);
    expect(log).not.toContain("EACCES");
    expect(log).toContain("Installed Pi CLI");

    const npmGlobalBin =
      "/home/coder/.coder-modules/coder-labs/pi/npm-global/bin";
    const binExists = await execContainer(id, [
      "test",
      "-x",
      `${npmGlobalBin}/pi`,
    ]);
    expect(binExists.exitCode).toBe(0);

    const profile = await readFileContainer(id, "/home/coder/.bashrc");
    expect(profile).toContain(npmGlobalBin);
  });

  test("anthropic-api-key", async () => {
    const apiKey = "test-api-key-123";
    const { id, coderEnvVars, scripts } = await setup({
      moduleVariables: {
        anthropic_api_key: apiKey,
      },
    });
    expect(coderEnvVars["ANTHROPIC_API_KEY"]).toBe(apiKey);
    expect(scripts.install).not.toContain(apiKey);
  });

  test("extra-env", async () => {
    const { coderEnvVars } = await setup({
      moduleVariables: {
        extra_env: JSON.stringify({ MISTRAL_API_KEY: "test-mistral-key" }),
      },
    });
    expect(coderEnvVars["MISTRAL_API_KEY"]).toBe("test-mistral-key");
  });

  test("default-project-trust-written-to-settings", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        default_project_trust: "never",
      },
    });
    await runScripts(id, scripts);
    const settings = await readFileContainer(
      id,
      "/home/coder/.pi/agent/settings.json",
    );
    expect(JSON.parse(settings).defaultProjectTrust).toBe("never");
  });

  test("existing-settings-are-preserved", async () => {
    const { id, scripts } = await setup();
    await execContainer(id, [
      "bash",
      "-c",
      "mkdir -p /home/coder/.pi/agent && printf '%s' '{\"theme\":\"dark\"}' > /home/coder/.pi/agent/settings.json",
    ]);
    await runScripts(id, scripts);
    const settings = JSON.parse(
      await readFileContainer(id, "/home/coder/.pi/agent/settings.json"),
    );
    expect(settings.theme).toBe("dark");
    expect(settings.defaultProjectTrust).toBe("always");
  });

  test("workdir-created-when-missing", async () => {
    const workdir = "/home/coder/pi-test-folder";
    const { id, scripts } = await setup({
      moduleVariables: { workdir },
    });
    await runScripts(id, scripts);
    const result = await execContainer(id, ["test", "-d", workdir]);
    expect(result.exitCode).toBe(0);
  });

  test("pre-post-install-scripts", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        pre_install_script: "#!/bin/bash\necho 'pi-pre-install-script'",
        post_install_script: "#!/bin/bash\necho 'pi-post-install-script'",
      },
    });
    await runScripts(id, scripts);

    const preInstallLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder-labs/pi/logs/pre_install.log",
    );
    expect(preInstallLog).toContain("pi-pre-install-script");

    const postInstallLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder-labs/pi/logs/post_install.log",
    );
    expect(postInstallLog).toContain("pi-post-install-script");
  });
});
