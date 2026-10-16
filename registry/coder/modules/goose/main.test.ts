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

// Replaces curl with a stub that prints `installer` as the downloaded script.
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
      "cat /tmp/goose-installer-fixture.sh",
    ].join("\n"),
  });
};

const installFixtureBinary = [
  'mkdir -p "$HOME/.local/bin"',
  `printf '#!/bin/sh\\necho " 1.54.0"\\n' > "$HOME/.local/bin/goose"`,
  'chmod +x "$HOME/.local/bin/goose"',
];

const recordInstallerEnv = [
  'printf "GOOSE_VERSION=[%s] CONFIGURE=%s\\n" "$GOOSE_VERSION" "$CONFIGURE" > /tmp/goose-installer-env',
];

const everythingYaml = dedent`
  everything:
    name: everything
    type: stdio
    cmd: npx
    args: ["-y", "@modelcontextprotocol/server-everything"]
    enabled: true
    timeout: 300
`;

const developerYaml = dedent`
  extensions:
    developer:
      display_name: Developer
      enabled: true
      name: developer
      timeout: 300
      type: builtin
`;

setDefaultTimeout(120 * 1000);

describe("goose", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path-writes-config", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const log = await installLog(id);
    expect(log).toContain("Skipping Goose installation");
    expect(log).not.toContain("agentapi");
    expect(await readFileContainer(id, configPath)).toBe(
      `GOOSE_PROVIDER: anthropic\nGOOSE_MODEL: claude-sonnet-4-6\n${developerYaml}\n`,
    );
  });

  test("preinstalled-binary-required-when-install-disabled", async () => {
    const { id, scripts } = await setup({ skipGooseMock: true });
    const resp = await runScript(id, "install", scripts.install);
    expect(resp.exitCode).not.toBe(0);
    expect(await installLog(id)).toContain("Error: Goose is not installed.");
  });

  test("official-installer-is-used-for-stable", async () => {
    const { id, scripts } = await setup({
      skipGooseMock: true,
      moduleVariables: { install_goose: "true" },
    });
    await mockInstallerDownload(id, [
      ...recordInstallerEnv,
      ...installFixtureBinary,
    ]);
    await runScripts(id, scripts);
    expect(await installLog(id)).toContain("Goose installed");
    expect(await readFileContainer(id, "/tmp/goose-curl-args")).toContain(
      "https://github.com/aaif-goose/goose/releases/download/stable/download_cli.sh",
    );
    expect(await readFileContainer(id, "/tmp/goose-installer-env")).toContain(
      "GOOSE_VERSION=[] CONFIGURE=false",
    );
  });

  test("pinned-version-is-passed-to-installer", async () => {
    const { id, scripts } = await setup({
      skipGooseMock: true,
      moduleVariables: { install_goose: "true", goose_version: "v1.53.0" },
    });
    await mockInstallerDownload(id, [
      ...recordInstallerEnv,
      ...installFixtureBinary,
    ]);
    await runScripts(id, scripts);
    expect(await readFileContainer(id, "/tmp/goose-installer-env")).toContain(
      "GOOSE_VERSION=[v1.53.0]",
    );
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
    expect(await installLog(id)).not.toContain("Goose installed");
  });

  test("symlinks-into-coder-script-bin-dir", async () => {
    const { id, scripts } = await setup();
    await execContainer(id, ["mkdir", "-p", "/tmp/coder-bin"]);
    await runScripts(id, scripts, { CODER_SCRIPT_BIN_DIR: "/tmp/coder-bin" });
    const link = await execContainer(id, ["readlink", "/tmp/coder-bin/goose"]);
    expect(link.stdout.trim()).toBe("/usr/bin/goose");
  });

  test("workdir-is-created", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const dir = await execContainer(id, ["test", "-d", projectDir]);
    expect(dir.exitCode).toBe(0);
  });

  test("additional-extensions-overwrite-config", async () => {
    const { id, scripts } = await setup({
      moduleVariables: { additional_extensions: everythingYaml },
    });
    await seedFile(id, configPath, "GOOSE_MODE: approve\n");
    await runScripts(id, scripts);
    const cfg = await readFileContainer(id, configPath);
    expect(cfg).not.toContain("approve");
    expect(cfg).toContain(
      `${developerYaml}\n  everything:\n    name: everything\n`,
    );
    expect(cfg).not.toContain("coder");
  });

  test("system-prompt-is-written-to-goosehints", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts, { GOOSE_SYSTEM_PROMPT: "be brief" });
    expect(
      await readFileContainer(id, "/home/coder/.config/goose/.goosehints"),
    ).toBe("be brief\n");
  });

  test("real-goose-loads-config", async () => {
    const { id, scripts } = await setup({
      skipGooseMock: true,
      moduleVariables: {
        install_goose: "true",
        goose_version: "v1.54.0",
        additional_extensions: everythingYaml,
      },
    });
    await runScripts(id, scripts);
    const info = await execContainer(id, [
      "bash",
      "-c",
      "$HOME/.local/bin/goose info -v",
    ]);
    expect(info.exitCode).toBe(0);
    expect(info.stdout).toContain("1.54.0");
    expect(info.stdout).toContain("GOOSE_PROVIDER: anthropic");
    expect(info.stdout).toContain("GOOSE_MODEL: claude-sonnet-4-6");
    expect(info.stdout).toContain("    developer:");
    expect(info.stdout).toContain("    everything:");
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
