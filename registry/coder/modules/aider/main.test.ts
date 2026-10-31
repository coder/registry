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
} from "../../../coder/modules/lib-agentapi/test-util";
import path from "path";

interface ModuleScripts {
  pre_install?: string;
  install: string;
  post_install?: string;
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
  const install = byDisplayName["Aider: Install Script"];
  if (!install) {
    throw new Error("install script not found in terraform state");
  }
  return {
    pre_install: byDisplayName["Aider: Pre-Install Script"],
    install,
    post_install: byDisplayName["Aider: Post-Install Script"],
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

interface SetupProps {
  skipAiderMock?: boolean;
  moduleVariables?: Record<string, string>;
}

const projectDir = "/home/coder/project";

const setup = async (
  props?: SetupProps,
): Promise<{
  id: string;
  coderEnvVars: Record<string, string>;
  scripts: ModuleScripts;
}> => {
  const moduleDir = path.resolve(import.meta.dir);
  const state = await runTerraformApply(moduleDir, {
    agent_id: "foo",
    model: "gemini",
    workdir: projectDir,
    install_aider: "false",
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

  await writeExecutable({
    containerId: id,
    filePath: "/usr/bin/coder",
    content: "#!/bin/bash\nexit 0\n",
  });
  if (!props?.skipAiderMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/aider",
      content: await Bun.file(
        path.join(moduleDir, "testdata", "aider-mock.sh"),
      ).text(),
    });
  }
  return { id, coderEnvVars, scripts };
};

// coder_env values reach coder_script processes through the agent environment.
const envArgs = (env: Record<string, string>) =>
  Object.entries(env).flatMap(([key, value]) => ["--env", `${key}=${value}`]);

const runScript = async (
  id: string,
  name: string,
  script: string,
  env: Record<string, string> = {},
) => {
  const target = `/tmp/coder-utils-${name}.sh`;
  await writeExecutable({ containerId: id, filePath: target, content: script });
  return execContainer(id, ["bash", "-c", target], envArgs(env));
};

const runScripts = async (
  id: string,
  scripts: ModuleScripts,
  env: Record<string, string> = {},
) => {
  const ordered: [string, string | undefined][] = [
    ["pre_install", scripts.pre_install],
    ["install", scripts.install],
    ["post_install", scripts.post_install],
  ];
  for (const [name, script] of ordered) {
    if (!script) continue;
    const resp = await runScript(id, name, script, env);
    if (resp.exitCode !== 0) {
      console.log(`script ${name} failed:`);
      console.log(resp.stdout);
      console.log(resp.stderr);
      throw new Error(`coder-utils ${name} script exited ${resp.exitCode}`);
    }
  }
};

const moduleLogDir = "/home/coder/.coder-modules/coder/aider/logs";
const installLog = (id: string) =>
  readFileContainer(id, `${moduleLogDir}/install.log`);
const configPath = "/home/coder/.aider.conf.yml";

// Replaces curl with a stub that serves `installer` as the downloaded script.
const mockInstallerDownload = async (id: string, installer: string[]) => {
  await writeExecutable({
    containerId: id,
    filePath: "/tmp/aider-installer-fixture.sh",
    content: ["#!/bin/sh", ...installer].join("\n"),
  });
  await writeExecutable({
    containerId: id,
    filePath: "/usr/local/bin/curl",
    content: [
      "#!/bin/bash",
      "printf '%s\\n' \"$*\" > /tmp/aider-curl-args",
      'while [ $# -gt 0 ]; do if [ "$1" = "--output" ]; then out="$2"; fi; shift; done',
      'cp /tmp/aider-installer-fixture.sh "$out"',
    ].join("\n"),
  });
};

setDefaultTimeout(60 * 1000);

describe("aider", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path-validates-existing-binary", async () => {
    const { id, coderEnvVars, scripts } = await setup();
    await runScripts(id, scripts);
    const log = await installLog(id);
    expect(log).toContain("Skipping Aider installation");
    expect(log).toContain("Validated existing Aider");
    expect(log).toContain("aider 0.86.0-mock");
    expect(log).toContain("Aider module setup completed.");
    expect(log).not.toContain("agentapi");
    expect(coderEnvVars["AIDER_MODEL"]).toBe("gemini");
    const cfg = await execContainer(id, ["test", "-e", configPath]);
    expect(cfg.exitCode).not.toBe(0);
  });

  test("preinstalled-binary-required-when-install-disabled", async () => {
    const { id, scripts } = await setup({ skipAiderMock: true });
    const resp = await runScript(id, "install", scripts.install);
    expect(resp.exitCode).not.toBe(0);
    const log = await installLog(id);
    expect(log).toContain("was not found or is not executable");
  });

  test("official-installer-is-used", async () => {
    const { id, scripts } = await setup({
      skipAiderMock: true,
      moduleVariables: { install_aider: "true" },
    });
    await mockInstallerDownload(id, [
      'printf "UV_NO_MODIFY_PATH=%s\\n" "$UV_NO_MODIFY_PATH" > /tmp/aider-installer-env',
      'mkdir -p "$HOME/.local/bin"',
      `printf '#!/bin/sh\\necho "aider 0.86.2"\\n' > "$HOME/.local/bin/aider"`,
      'chmod +x "$HOME/.local/bin/aider"',
    ]);
    await runScripts(id, scripts);
    const log = await installLog(id);
    expect(log).toContain("Installed Aider");
    expect(log).toContain("Aider version: aider 0.86.2");
    const curlArgs = await readFileContainer(id, "/tmp/aider-curl-args");
    expect(curlArgs).toContain("https://aider.chat/install.sh");
    expect(curlArgs).toContain("--retry 2");
    expect(curlArgs).toContain("--connect-timeout 10");
    expect(curlArgs).toContain("--max-time 300");
    const installerEnv = await readFileContainer(
      id,
      "/tmp/aider-installer-env",
    );
    expect(installerEnv.trim()).toBe("UV_NO_MODIFY_PATH=1");
    const bashrc = await readFileContainer(id, "/home/coder/.bashrc");
    expect(bashrc).toContain("/home/coder/.local/bin");
  });

  test("installer-download-failure-is-terminal", async () => {
    const { id, scripts } = await setup({
      skipAiderMock: true,
      moduleVariables: { install_aider: "true" },
    });
    await writeExecutable({
      containerId: id,
      filePath: "/usr/local/bin/curl",
      content: "#!/bin/bash\nexit 22\n",
    });
    const resp = await runScript(id, "install", scripts.install);
    expect(resp.exitCode).not.toBe(0);
    const log = await installLog(id);
    expect(log).toContain("could not be downloaded");
  });

  test("symlinks-into-coder-script-bin-dir", async () => {
    const { id, scripts } = await setup();
    await execContainer(id, ["mkdir", "-p", "/tmp/coder-bin"]);
    await runScripts(id, scripts, { CODER_SCRIPT_BIN_DIR: "/tmp/coder-bin" });
    const link = await execContainer(id, ["readlink", "/tmp/coder-bin/aider"]);
    expect(link.stdout.trim()).toBe("/usr/bin/aider");
  });

  test("workdir-is-created", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const dir = await execContainer(id, ["test", "-d", projectDir]);
    expect(dir.exitCode).toBe(0);
  });

  test("base-aider-config-is-written-verbatim", async () => {
    const config = "model: sonnet\nread:\n  - CONVENTIONS.md\ndark-mode: true";
    const { id, scripts } = await setup({
      moduleVariables: { base_aider_config: config },
    });
    await runScripts(id, scripts);
    expect(await readFileContainer(id, configPath)).toBe(`${config}\n`);
    expect(await installLog(id)).toContain(
      `Aider config written: ${configPath}`,
    );
  });

  test("existing-config-is-kept-without-base-aider-config", async () => {
    const { id, scripts } = await setup();
    await execContainer(id, [
      "bash",
      "-c",
      `echo 'dark-mode: true' > ${configPath}`,
    ]);
    await runScripts(id, scripts);
    expect((await readFileContainer(id, configPath)).trim()).toBe(
      "dark-mode: true",
    );
    expect(await installLog(id)).toContain("No base_aider_config provided");
  });

  test("api-key-is-only-in-coder-env", async () => {
    const secret = "sk-ant-test-secret-123";
    const { id, coderEnvVars, scripts } = await setup({
      moduleVariables: {
        ai_provider: "anthropic",
        model: "sonnet",
        api_key: secret,
      },
    });
    expect(coderEnvVars["ANTHROPIC_API_KEY"]).toBe(secret);
    expect(coderEnvVars["AIDER_MODEL"]).toBe("sonnet");
    expect(scripts.install).not.toContain(secret);
    expect(scripts.install).not.toContain(
      Buffer.from(secret).toString("base64"),
    );
    await runScripts(id, scripts, coderEnvVars);
    expect(await installLog(id)).not.toContain(secret);
  });

  test("pre-post-install-scripts", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        pre_install_script: "#!/bin/bash\necho 'aider-pre-install-script'",
        post_install_script: "#!/bin/bash\necho 'aider-post-install-script'",
      },
    });
    await runScripts(id, scripts);
    expect(
      await readFileContainer(id, `${moduleLogDir}/pre_install.log`),
    ).toContain("aider-pre-install-script");
    expect(
      await readFileContainer(id, `${moduleLogDir}/post_install.log`),
    ).toContain("aider-post-install-script");
  });
});
