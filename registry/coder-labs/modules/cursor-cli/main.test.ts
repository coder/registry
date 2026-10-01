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
    const key = `Cursor CLI: ${suffix}`;
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
  skipCursorMock?: boolean;
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
    install_cursor_cli: "false",
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
  if (!props?.skipCursorMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/cursor-agent",
      content: await Bun.file(
        path.join(moduleDir, "testdata", "cursor-cli-mock.sh"),
      ).text(),
    });
  }
  return { id, coderEnvVars, scripts };
};

const runScript = async (id: string, name: string, script: string) => {
  const target = `/tmp/coder-utils-${name}.sh`;
  await writeExecutable({ containerId: id, filePath: target, content: script });
  return execContainer(id, ["bash", "-c", target]);
};

const runScripts = async (id: string, scripts: ModuleScripts) => {
  const ordered: [string, string | undefined][] = [
    ["pre_install", scripts.pre_install],
    ["install", scripts.install],
    ["post_install", scripts.post_install],
  ];
  for (const [name, script] of ordered) {
    if (!script) continue;
    const resp = await runScript(id, name, script);
    if (resp.exitCode !== 0) {
      console.log(`script ${name} failed:`);
      console.log(resp.stdout);
      console.log(resp.stderr);
      throw new Error(`coder-utils ${name} script exited ${resp.exitCode}`);
    }
  }
};

const moduleLogDir = "/home/coder/.coder-modules/coder-labs/cursor-cli/logs";
const installLog = (id: string) =>
  readFileContainer(id, `${moduleLogDir}/install.log`);
const mcpConfigPath = "/home/coder/.cursor/mcp.json";
const trustMarkerPath =
  "/home/coder/.cursor/projects/home-coder-project/.workspace-trusted";

setDefaultTimeout(60 * 1000);

describe("cursor-cli", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path-validates-existing-binary", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const log = await installLog(id);
    expect(log).toContain("Skipping Cursor CLI installation");
    expect(log).toContain("Validated existing Cursor CLI");
    expect(log).toContain("Cursor CLI module setup completed.");
    // No agentapi or task-reporting leftovers.
    expect(log).not.toContain("agentapi");
  });

  test("preinstalled-binary-required-when-install-disabled", async () => {
    const { id, scripts } = await setup({ skipCursorMock: true });
    const resp = await runScript(id, "install", scripts.install);
    expect(resp.exitCode).not.toBe(0);
    const log = await installLog(id);
    expect(log).toContain("was not found or is not executable");
  });

  test("official-installer-is-used", async () => {
    const { id, scripts } = await setup({
      skipCursorMock: true,
      moduleVariables: { install_cursor_cli: "true" },
    });
    await writeExecutable({
      containerId: id,
      filePath: "/tmp/cursor-installer-fixture.sh",
      content: [
        "#!/usr/bin/env bash",
        'mkdir -p "$HOME/.local/bin"',
        `cat > "$HOME/.local/bin/cursor-agent" <<'EOF'`,
        "#!/bin/sh",
        'if [ "$1" = "--version" ]; then echo "2026.02.02-fixture"; fi',
        "EOF",
        'chmod +x "$HOME/.local/bin/cursor-agent"',
      ].join("\n"),
    });
    await writeExecutable({
      containerId: id,
      filePath: "/usr/local/bin/curl",
      content: [
        "#!/bin/bash",
        "printf '%s\\n' \"$*\" > /tmp/cursor-curl-args",
        'while [ $# -gt 0 ]; do if [ "$1" = "--output" ]; then out="$2"; fi; shift; done',
        'cp /tmp/cursor-installer-fixture.sh "$out"',
      ].join("\n"),
    });
    await runScripts(id, scripts);
    const log = await installLog(id);
    expect(log).toContain("Installed Cursor CLI");
    expect(log).toContain("2026.02.02-fixture");
    const curlArgs = await readFileContainer(id, "/tmp/cursor-curl-args");
    expect(curlArgs).toContain("https://cursor.com/install");
    expect(curlArgs).toContain("--retry 2");
    expect(curlArgs).toContain("--connect-timeout 10");
    expect(curlArgs).toContain("--max-time 300");
  });

  test("installer-download-failure-is-terminal", async () => {
    const { id, scripts } = await setup({
      skipCursorMock: true,
      moduleVariables: { install_cursor_cli: "true" },
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

  test("workdir-created-and-trusted", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const dir = await execContainer(id, ["test", "-d", projectDir]);
    expect(dir.exitCode).toBe(0);
    const marker = JSON.parse(await readFileContainer(id, trustMarkerPath));
    expect(marker.workspacePath).toBe(projectDir);
    expect(marker.trustedAt).toBeDefined();
  });

  test("existing-trust-marker-is-preserved", async () => {
    const { id, scripts } = await setup();
    const seed = JSON.stringify({
      trustedAt: "2020-01-01T00:00:00.000Z",
      workspacePath: projectDir,
      trustMethod: "dialog",
    });
    await execContainer(id, [
      "bash",
      "-c",
      `mkdir -p "$(dirname '${trustMarkerPath}')" && echo '${seed}' > '${trustMarkerPath}'`,
    ]);
    await runScripts(id, scripts);
    const marker = JSON.parse(await readFileContainer(id, trustMarkerPath));
    expect(marker.trustedAt).toBe("2020-01-01T00:00:00.000Z");
  });

  test("no-workdir-no-trust-marker", async () => {
    const { id, scripts } = await setup({ moduleVariables: { workdir: "" } });
    await runScripts(id, scripts);
    const resp = await execContainer(id, [
      "bash",
      "-c",
      "test -e /home/coder/.cursor/projects && echo EXISTS || echo ABSENT",
    ]);
    expect(resp.stdout.trim()).toBe("ABSENT");
  });

  test("writes-mcp-servers-without-coder-server", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        mcp: JSON.stringify({
          mcpServers: {
            playwright: { command: "npx", args: ["-y", "@playwright/mcp"] },
          },
        }),
      },
    });
    await runScripts(id, scripts);
    const mcp = JSON.parse(await readFileContainer(id, mcpConfigPath));
    expect(mcp.mcpServers.playwright.command).toBe("npx");
    expect(mcp.mcpServers.coder).toBeUndefined();
    // The project-level mcp.json is no longer written.
    const projectMcp = await execContainer(id, [
      "test",
      "-e",
      `${projectDir}/.cursor/mcp.json`,
    ]);
    expect(projectMcp.exitCode).not.toBe(0);
  });

  test("merges-mcp-config-existing-servers-win", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        mcp: JSON.stringify({
          mcpServers: {
            shared: { command: "module-command" },
            extra: { command: "extra-command" },
          },
        }),
      },
    });
    const seed = JSON.stringify({
      mcpServers: {
        shared: { command: "existing-command" },
        seeded: { command: "seeded-command" },
      },
    });
    await execContainer(id, [
      "bash",
      "-c",
      `mkdir -p /home/coder/.cursor && echo '${seed}' > ${mcpConfigPath}`,
    ]);
    await runScripts(id, scripts);
    const mcp = JSON.parse(await readFileContainer(id, mcpConfigPath));
    expect(mcp.mcpServers.shared.command).toBe("existing-command");
    expect(mcp.mcpServers.seeded.command).toBe("seeded-command");
    expect(mcp.mcpServers.extra.command).toBe("extra-command");
  });

  test("invalid-existing-mcp-config-is-backed-up", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        mcp: JSON.stringify({ mcpServers: { extra: { command: "x" } } }),
      },
    });
    await execContainer(id, [
      "bash",
      "-c",
      `mkdir -p /home/coder/.cursor && echo '{ // jsonc' > ${mcpConfigPath}`,
    ]);
    await runScripts(id, scripts);
    const mcp = JSON.parse(await readFileContainer(id, mcpConfigPath));
    expect(mcp.mcpServers.extra.command).toBe("x");
    const backup = await readFileContainer(id, `${mcpConfigPath}.bak`);
    expect(backup).toContain("// jsonc");
  });

  test("rules-files-written-to-workdir", async () => {
    const content = "---\nalwaysApply: true\n---\n\n- Use TypeScript\n";
    const { id, scripts } = await setup({
      moduleVariables: {
        rules_files: JSON.stringify({ "typescript.mdc": content }),
      },
    });
    await runScripts(id, scripts);
    const rule = await readFileContainer(
      id,
      `${projectDir}/.cursor/rules/typescript.mdc`,
    );
    expect(rule).toBe(content);
  });

  test("api-key-env-var-not-in-script", async () => {
    const apiKey = "test-cursor-api-key-123";
    const { coderEnvVars, scripts } = await setup({
      moduleVariables: { api_key: apiKey },
    });
    expect(coderEnvVars["CURSOR_API_KEY"]).toBe(apiKey);
    expect(scripts.install).not.toContain(apiKey);
    expect(scripts.install).not.toContain(
      Buffer.from(apiKey).toString("base64"),
    );
  });

  test("pre-post-install-scripts", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        pre_install_script: "#!/bin/bash\necho 'cursor-pre-install-script'",
        post_install_script: "#!/bin/bash\necho 'cursor-post-install-script'",
      },
    });
    await runScripts(id, scripts);
    expect(
      await readFileContainer(id, `${moduleLogDir}/pre_install.log`),
    ).toContain("cursor-pre-install-script");
    expect(
      await readFileContainer(id, `${moduleLogDir}/post_install.log`),
    ).toContain("cursor-post-install-script");
  });
});
