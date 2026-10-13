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
import { extractCoderEnvVars, writeExecutable } from "../agentapi/test-util";
import dedent from "dedent";
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
    const key = `Goose: ${suffix}`;
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
  skipGooseMock?: boolean;
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
    workdir: projectDir,
    install_goose: "false",
    goose_provider: "anthropic",
    goose_model: "claude-sonnet-4-6",
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
  if (!props?.skipGooseMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/goose",
      content: await Bun.file(
        path.join(moduleDir, "testdata", "goose-mock.sh"),
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

const moduleLogDir = "/home/coder/.coder-modules/coder/goose/logs";
const installLog = (id: string) =>
  readFileContainer(id, `${moduleLogDir}/install.log`);
const configPath = "/home/coder/.config/goose/config.yaml";

const seedFile = async (id: string, filePath: string, content: string) => {
  const encoded = Buffer.from(content).toString("base64");
  await execContainer(id, [
    "bash",
    "-c",
    `mkdir -p "$(dirname '${filePath}')" && echo '${encoded}' | base64 -d > '${filePath}'`,
  ]);
};

// Replaces curl with a stub that serves `installer` as the downloaded script.
const mockInstallerDownload = async (id: string, installer: string[]) => {
  await writeExecutable({
    containerId: id,
    filePath: "/tmp/goose-installer-fixture.sh",
    content: ["#!/usr/bin/env bash", ...installer].join("\n"),
  });
  await writeExecutable({
    containerId: id,
    filePath: "/usr/local/bin/curl",
    content: [
      "#!/bin/bash",
      "printf '%s\\n' \"$*\" > /tmp/goose-curl-args",
      'while [ $# -gt 0 ]; do if [ "$1" = "--output" ]; then out="$2"; fi; shift; done',
      'cp /tmp/goose-installer-fixture.sh "$out"',
    ].join("\n"),
  });
};

const installFixtureBinary = (version: string) => [
  'mkdir -p "$HOME/.local/bin"',
  `printf '#!/bin/sh\\necho " ${version}"\\n' > "$HOME/.local/bin/goose"`,
  'chmod +x "$HOME/.local/bin/goose"',
];

const recordInstallerEnv = [
  'printf "GOOSE_VERSION=[%s] CONFIGURE=%s PWD=%s\\n" "$GOOSE_VERSION" "$CONFIGURE" "$PWD" > /tmp/goose-installer-env',
];

// Key order matches Terraform's jsonencode, which sorts object keys.
const everything = {
  args: ["-y", "@modelcontextprotocol/server-everything"],
  cmd: "npx",
  enabled: true,
  name: "everything",
  timeout: 300,
  type: "stdio",
};

const everythingYaml = dedent`
  everything:
    name: everything
    type: stdio
    cmd: npx
    args: ["-y", "@modelcontextprotocol/server-everything"]
    enabled: true
    timeout: 300
`;

const flowEntry = (name: string, value: unknown) =>
  `${JSON.stringify(name)}: ${JSON.stringify(value)}`;

setDefaultTimeout(120 * 1000);

describe("goose", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path-validates-existing-binary", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const log = await installLog(id);
    expect(log).toContain("Skipping Goose installation");
    expect(log).toContain("Validated existing Goose");
    expect(log).toContain("1.54.0-mock");
    expect(log).toContain("Goose module setup completed.");
    expect(log).not.toContain("agentapi");
    const cfg = await execContainer(id, ["test", "-e", configPath]);
    expect(cfg.exitCode).not.toBe(0);
  });

  test("provider-and-model-are-exported", async () => {
    const { coderEnvVars, scripts } = await setup();
    expect(coderEnvVars["GOOSE_PROVIDER"]).toBe("anthropic");
    expect(coderEnvVars["GOOSE_MODEL"]).toBe("claude-sonnet-4-6");
    expect(scripts.install).not.toContain("claude-sonnet-4-6");
  });

  test("preinstalled-binary-required-when-install-disabled", async () => {
    const { id, scripts } = await setup({ skipGooseMock: true });
    const resp = await runScript(id, "install", scripts.install);
    expect(resp.exitCode).not.toBe(0);
    const log = await installLog(id);
    expect(log).toContain("was not found or is not executable");
  });

  test("official-installer-is-used-for-stable", async () => {
    const { id, scripts } = await setup({
      skipGooseMock: true,
      moduleVariables: { install_goose: "true" },
    });
    await mockInstallerDownload(id, [
      ...recordInstallerEnv,
      ...installFixtureBinary("1.54.0"),
    ]);
    await runScripts(id, scripts);
    const log = await installLog(id);
    expect(log).toContain("Installed Goose");
    expect(log).toContain("Goose version:  1.54.0");
    const curlArgs = await readFileContainer(id, "/tmp/goose-curl-args");
    expect(curlArgs).toContain(
      "https://github.com/aaif-goose/goose/releases/download/stable/download_cli.sh",
    );
    expect(curlArgs).toContain("--retry 2");
    expect(curlArgs).toContain("--connect-timeout 10");
    expect(curlArgs).toContain("--max-time 300");
    const installerEnv = await readFileContainer(
      id,
      "/tmp/goose-installer-env",
    );
    expect(installerEnv).toContain("GOOSE_VERSION=[] CONFIGURE=false");
    // The installer downloads into its working directory, so it must run in a temp dir.
    expect(installerEnv).toMatch(/PWD=\/tmp\/tmp\.\S+/);
    const bashrc = await readFileContainer(id, "/home/coder/.bashrc");
    expect(bashrc).toContain("/home/coder/.local/bin");
  });

  test("pinned-version-is-passed-to-installer", async () => {
    const { id, scripts } = await setup({
      skipGooseMock: true,
      moduleVariables: { install_goose: "true", goose_version: "v1.53.0" },
    });
    await mockInstallerDownload(id, [
      ...recordInstallerEnv,
      ...installFixtureBinary("1.53.0"),
    ]);
    await runScripts(id, scripts);
    const installerEnv = await readFileContainer(
      id,
      "/tmp/goose-installer-env",
    );
    expect(installerEnv).toContain("GOOSE_VERSION=[v1.53.0]");
  });

  test("installer-download-failure-is-terminal", async () => {
    const { id, scripts } = await setup({
      skipGooseMock: true,
      moduleVariables: { install_goose: "true" },
    });
    await writeExecutable({
      containerId: id,
      filePath: "/usr/local/bin/curl",
      content: "#!/bin/bash\nexit 22\n",
    });
    const resp = await runScript(id, "install", scripts.install);
    expect(resp.exitCode).not.toBe(0);
    expect(await installLog(id)).toContain("could not be downloaded");
  });

  test("workdir-is-created", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const dir = await execContainer(id, ["test", "-d", projectDir]);
    expect(dir.exitCode).toBe(0);
  });

  test("extensions-are-written-to-new-config", async () => {
    const { id, scripts } = await setup({
      moduleVariables: { additional_extensions: everythingYaml },
    });
    await runScripts(id, scripts);
    const cfg = await readFileContainer(id, configPath);
    expect(cfg).toBe(`extensions:\n  ${flowEntry("everything", everything)}\n`);
    expect(cfg).not.toContain("coder");
    expect(cfg).not.toContain("GOOSE_PROVIDER");
    expect(await installLog(id)).toContain("Added extension 'everything'");
  });

  test("merges-extensions-existing-wins", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        additional_extensions: dedent`
          mine:
            name: mine
            type: stdio
            cmd: module-cmd
          extra:
            name: extra
            type: stdio
            cmd: extra-cmd
        `,
      },
    });
    const existing = dedent`
      GOOSE_MODE: approve
      extensions:
          # keep this comment
          mine:
              name: mine
              type: stdio
              cmd: user-cmd
              args:
              - a
          'quoted':
              name: quoted
              type: stdio
              cmd: q
      GOOSE_CLI_THEME: dark
    `;
    await seedFile(id, configPath, existing + "\n");
    await runScripts(id, scripts);
    const cfg = await readFileContainer(id, configPath);
    const extra = flowEntry("extra", {
      cmd: "extra-cmd",
      name: "extra",
      type: "stdio",
    });
    expect(cfg).toBe(
      existing.replace("extensions:\n", `extensions:\n    ${extra}\n`) + "\n",
    );
    const log = await installLog(id);
    expect(log).toContain(
      `extension 'mine' already exists in ${configPath}, keeping the existing one.`,
    );
    expect(log).not.toContain("extension 'extra' already exists");
    expect(log).toContain("Added extension 'extra'");
  });

  test("rerun-is-idempotent", async () => {
    const { id, scripts } = await setup({
      moduleVariables: { additional_extensions: everythingYaml },
    });
    await runScripts(id, scripts);
    const first = await readFileContainer(id, configPath);
    await runScripts(id, scripts);
    expect(await readFileContainer(id, configPath)).toBe(first);
    expect(await installLog(id)).toContain(
      "All additional_extensions already exist",
    );
  });

  test("config-without-extensions-key-is-appended", async () => {
    const { id, scripts } = await setup({
      moduleVariables: { additional_extensions: everythingYaml },
    });
    await seedFile(id, configPath, "GOOSE_MODE: approve");
    await runScripts(id, scripts);
    expect(await readFileContainer(id, configPath)).toBe(
      `GOOSE_MODE: approve\nextensions:\n  ${flowEntry("everything", everything)}\n`,
    );
  });

  test("empty-inline-extensions-are-replaced", async () => {
    const { id, scripts } = await setup({
      moduleVariables: { additional_extensions: everythingYaml },
    });
    await seedFile(id, configPath, "extensions: {}\nGOOSE_MODE: approve\n");
    await runScripts(id, scripts);
    expect(await readFileContainer(id, configPath)).toBe(
      `extensions:\n  ${flowEntry("everything", everything)}\nGOOSE_MODE: approve\n`,
    );
  });

  test("non-empty-inline-extensions-are-left-unchanged", async () => {
    const { id, scripts } = await setup({
      moduleVariables: { additional_extensions: everythingYaml },
    });
    const existing = "extensions: {mine: {name: mine, type: stdio, cmd: x}}\n";
    await seedFile(id, configPath, existing);
    await runScripts(id, scripts);
    expect(await readFileContainer(id, configPath)).toBe(existing);
    expect(await installLog(id)).toContain(
      "inline format the module cannot extend",
    );
  });

  test("symlinked-config-is-written-through", async () => {
    const { id, scripts } = await setup({
      moduleVariables: { additional_extensions: everythingYaml },
    });
    await seedFile(id, "/home/coder/dotfiles/goose.yaml", "GOOSE_MODE: auto\n");
    await execContainer(id, [
      "bash",
      "-c",
      `mkdir -p "$(dirname ${configPath})" && ln -s /home/coder/dotfiles/goose.yaml ${configPath}`,
    ]);
    await runScripts(id, scripts);
    const link = await execContainer(id, ["test", "-L", configPath]);
    expect(link.exitCode).toBe(0);
    expect(
      await readFileContainer(id, "/home/coder/dotfiles/goose.yaml"),
    ).toContain(flowEntry("everything", everything));
  });

  test("goose-path-root-is-respected", async () => {
    const root = "/home/coder/goose-root";
    const { id, scripts } = await setup({
      moduleVariables: { additional_extensions: everythingYaml },
    });
    await runScripts(id, scripts, { GOOSE_PATH_ROOT: root });
    expect(await readFileContainer(id, `${root}/config/config.yaml`)).toContain(
      flowEntry("everything", everything),
    );
    const fallback = await execContainer(id, ["test", "-e", configPath]);
    expect(fallback.exitCode).not.toBe(0);
  });

  test("real-goose-loads-merged-config", async () => {
    const { id, coderEnvVars, scripts } = await setup({
      skipGooseMock: true,
      moduleVariables: {
        install_goose: "true",
        goose_version: "v1.54.0",
        additional_extensions: everythingYaml,
      },
    });
    await seedFile(
      id,
      configPath,
      "extensions:\n  mine:\n    name: mine\n    type: stdio\n    cmd: user-cmd\n    enabled: true\n",
    );
    await runScripts(id, scripts, coderEnvVars);
    const info = await execContainer(
      id,
      ["bash", "-c", "$HOME/.local/bin/goose info -v"],
      envArgs(coderEnvVars),
    );
    expect(info.exitCode).toBe(0);
    expect(info.stdout).toContain("1.54.0");
    expect(info.stdout).toContain("GOOSE_PROVIDER: anthropic");
    expect(info.stdout).toContain("GOOSE_MODEL: claude-sonnet-4-6");
    expect(info.stdout).toContain("    everything:");
    expect(info.stdout).toContain("'@modelcontextprotocol/server-everything'");
    expect(info.stdout).toContain("cmd: user-cmd");
  });

  test("pre-post-install-scripts", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        pre_install_script: "#!/bin/bash\necho 'goose-pre-install-script'",
        post_install_script: "#!/bin/bash\necho 'goose-post-install-script'",
      },
    });
    await runScripts(id, scripts);
    expect(
      await readFileContainer(id, `${moduleLogDir}/pre_install.log`),
    ).toContain("goose-pre-install-script");
    expect(
      await readFileContainer(id, `${moduleLogDir}/post_install.log`),
    ).toContain("goose-post-install-script");
  });
});
