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
  runTerraformApply,
  runTerraformInit,
  runContainer,
  removeContainer,
  type TerraformState,
} from "~test";
import { loadTestFile, writeExecutable } from "../agentapi/test-util";

// Terraform state resource attributes are untyped JSON; this alias makes the
// shape explicit everywhere we unpack it.
type ResourceAttributes = Record<string, unknown>;

const getStringAttr = (attrs: ResourceAttributes, key: string): string =>
  String(attrs[key] ?? "");

/**
 * Walk every instance of every `coder_env` resource and return a flat map of
 * env var names to values. The `extractCoderEnvVars` helper in
 * `agentapi/test-util.ts` only reads `instances[0]`, which misses every
 * `for_each` entry past the first. This local version covers all instances.
 */
const extractCoderEnvVars = (state: TerraformState): Record<string, string> => {
  const envVars: Record<string, string> = {};
  for (const resource of state.resources) {
    if (resource.type !== "coder_env") continue;
    for (const instance of resource.instances) {
      const attrs = instance.attributes as ResourceAttributes;
      const name = getStringAttr(attrs, "name");
      const value = getStringAttr(attrs, "value");
      if (name && value) envVars[name] = value;
    }
  }
  return envVars;
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
  skipClaudeMock?: boolean;
  moduleVariables?: Record<string, string>;
}

// Order scripts in the same sequence coder-utils enforces at runtime via
// `coder exp sync`: first pre_install, then install, then post_install.
const SCRIPT_ORDER = [
  "Pre-Install Script",
  "Install Script",
  "Post-Install Script",
];

const collectScripts = (state: TerraformState): string[] => {
  const scripts: { displayName: string; script: string }[] = [];
  for (const resource of state.resources) {
    if (resource.type !== "coder_script") continue;
    for (const instance of resource.instances) {
      const attrs = instance.attributes as ResourceAttributes;
      scripts.push({
        displayName: getStringAttr(attrs, "display_name"),
        script: getStringAttr(attrs, "script"),
      });
    }
  }
  scripts.sort(
    (a, b) =>
      SCRIPT_ORDER.indexOf(a.displayName) - SCRIPT_ORDER.indexOf(b.displayName),
  );
  return scripts.map((s) => s.script);
};

const setup = async (
  props?: SetupProps,
): Promise<{ id: string; coderEnvVars: Record<string, string> }> => {
  const moduleVariables: Record<string, string> = {
    agent_id: "foo",
    install_claude_code: props?.skipClaudeMock ? "true" : "false",
    ...props?.moduleVariables,
  };
  const state = await runTerraformApply(import.meta.dir, moduleVariables);
  const scripts = collectScripts(state);
  const coderEnvVars = extractCoderEnvVars(state);

  const id = await runContainer("codercom/enterprise-node:latest");
  registerCleanup(async () => {
    if (
      process.env["DEBUG"] === "true" ||
      process.env["DEBUG"] === "1" ||
      process.env["DEBUG"] === "yes"
    ) {
      console.log(`Not removing container ${id} in debug mode`);
      console.log(`Run "docker rm -f ${id}" to remove it manually.`);
    } else {
      await removeContainer(id);
    }
  });

  // `coder-utils` wraps each script with `coder exp sync` calls. Install a
  // no-op mock so the script runs in the minimal test container.
  await writeExecutable({
    containerId: id,
    filePath: "/usr/bin/coder",
    content: await loadTestFile(import.meta.dir, "coder-mock.sh"),
  });

  if (!props?.skipClaudeMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/claude",
      content: await loadTestFile(import.meta.dir, "claude-mock.sh"),
    });
  }

  // Concatenate scripts in dependency order into a single driver. Each script
  // runs in its own subshell so that `set -e` and `exit` stay contained.
  const driver = scripts
    .map((s, i) => `(\n# --- script ${i} ---\n${s}\n)`)
    .join("\n");
  await writeExecutable({
    containerId: id,
    filePath: "/home/coder/script.sh",
    content: driver,
  });

  return { id, coderEnvVars };
};

const runModuleScripts = async (id: string, env?: Record<string, string>) => {
  const entries = env ? Object.entries(env) : [];
  const envArgs = entries.length
    ? entries
        .map(([key, value]) => `export ${key}="${value.replace(/"/g, '\\"')}"`)
        .join(" && ") + " && "
    : "";
  const resp = await execContainer(id, [
    "bash",
    "-c",
    `${envArgs}set -o errexit; set -o pipefail; cd /home/coder && ./script.sh 2>&1 | tee /home/coder/script.log`,
  ]);
  if (resp.exitCode !== 0) {
    console.log(resp.stdout);
    console.log(resp.stderr);
  }
  return resp;
};

setDefaultTimeout(60 * 1000);

describe("claude-code", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("install-script-runs-with-mock", async () => {
    // Default setup: install_claude_code=false with a mocked claude binary.
    // Verifies that install.sh is assembled, written by coder-utils, executed
    // on the agent, and leaves a readable install.log.
    const { id } = await setup();
    await runModuleScripts(id);
    const installLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/claude-code/install.log",
    );
    expect(installLog).toContain("ARG_INSTALL_CLAUDE_CODE");
    expect(installLog).toContain("Skipping Claude Code installation");
  });

  test("install-claude-code-version", async () => {
    const version_to_install = "1.0.40";
    const { id, coderEnvVars } = await setup({
      skipClaudeMock: true,
      moduleVariables: {
        install_claude_code: "true",
        claude_code_version: version_to_install,
      },
    });
    await runModuleScripts(id, coderEnvVars);
    const resp = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.coder-modules/claude-code/install.log",
    ]);
    expect(resp.stdout).toContain(version_to_install);
  });

  test("install-claude-code-latest", async () => {
    const { id, coderEnvVars } = await setup({
      skipClaudeMock: true,
      moduleVariables: {
        install_claude_code: "true",
      },
    });
    await runModuleScripts(id, coderEnvVars);
    const resp = await execContainer(id, [
      "bash",
      "-c",
      'export PATH="$HOME/.local/bin:$PATH" && claude --version',
    ]);
    expect(resp.exitCode).toBe(0);
    expect(resp.stdout).toMatch(/\d+\.\d+\.\d+/);
  });

  test("env-map-passthrough", async () => {
    const { id, coderEnvVars } = await setup({
      moduleVariables: {
        env: JSON.stringify({
          ANTHROPIC_API_KEY: "sk-test-api-key-123",
          CLAUDE_CODE_OAUTH_TOKEN: "oauth-live-token",
          ANTHROPIC_MODEL: "opus",
          DISABLE_AUTOUPDATER: "1",
          CUSTOM_VAR: "hello",
        }),
      },
    });
    expect(coderEnvVars["ANTHROPIC_API_KEY"]).toBe("sk-test-api-key-123");
    expect(coderEnvVars["CLAUDE_CODE_OAUTH_TOKEN"]).toBe("oauth-live-token");
    expect(coderEnvVars["ANTHROPIC_MODEL"]).toBe("opus");
    expect(coderEnvVars["DISABLE_AUTOUPDATER"]).toBe("1");
    expect(coderEnvVars["CUSTOM_VAR"]).toBe("hello");
    expect(coderEnvVars["CLAUDE_API_KEY"]).toBeUndefined();
    // Export the Terraform-declared env vars into the script execution
    // context so the install script sees the values the module produced.
    await runModuleScripts(id, coderEnvVars);
  });

  test("no-claude-no-mcp-is-fine", async () => {
    // install_claude_code=false and no MCP requested: install log records
    // the note and no resource tries to call the claude binary. The
    // overall coder-utils pipeline succeeds.
    const { id, coderEnvVars } = await setup({
      moduleVariables: {
        install_claude_code: "false",
      },
    });
    // Remove the claude mock so command -v claude fails in the container.
    // /usr/bin requires root, so exec as root.
    await execContainer(
      id,
      [
        "bash",
        "-c",
        "rm -f /usr/bin/claude /home/coder/.local/bin/claude 2>/dev/null; hash -r",
      ],
      ["--user", "root"],
    );
    const resp = await runModuleScripts(id, coderEnvVars);
    expect(resp.exitCode).toBe(0);
    const installLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/claude-code/install.log",
    );
    expect(installLog).toContain("claude binary not found on PATH");
  });

  test("mcp-without-claude-fails-loudly", async () => {
    // install_claude_code=false + mcp requested + no claude binary: the
    // install script must exit non-zero with a clear error in the log
    // instead of silently no-oping every claude mcp add-json call.
    const { id, coderEnvVars } = await setup({
      moduleVariables: {
        install_claude_code: "false",
        mcp: JSON.stringify({
          mcpServers: { test: { command: "test-cmd" } },
        }),
      },
    });
    await execContainer(
      id,
      [
        "bash",
        "-c",
        "rm -f /usr/bin/claude /home/coder/.local/bin/claude 2>/dev/null; hash -r",
      ],
      ["--user", "root"],
    );
    const resp = await runModuleScripts(id, coderEnvVars);
    expect(resp.exitCode).not.toBe(0);
    const installLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/claude-code/install.log",
    );
    expect(installLog).toContain(
      "MCP configuration was provided but the claude binary is not on PATH",
    );
  });

  test("claude-mcp-inline-user-scope", async () => {
    const mcpConfig = JSON.stringify({
      mcpServers: {
        "test-server": {
          command: "test-cmd",
          args: ["--config", "test.json"],
        },
      },
    });
    const { id } = await setup({
      moduleVariables: {
        mcp: mcpConfig,
      },
    });
    await runModuleScripts(id);

    const installLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/claude-code/install.log",
    );
    expect(installLog).toContain("claude mcp add-json --scope user");
    expect(installLog).toContain("test-server");
  });

  test("claude-mcp-remote-user-scope", async () => {
    // HTTPS URL on an unreachable port so the fetch fails with the expected
    // "Warning: Failed to fetch" message (the module validation enforces
    // https:// so plain http URLs are rejected at plan time).
    const failingUrl = "https://127.0.0.1:19999/mcp.json";
    const successUrl =
      "https://raw.githubusercontent.com/coder/coder/main/.mcp.json";

    const { id, coderEnvVars } = await setup({
      skipClaudeMock: true,
      moduleVariables: {
        mcp_config_remote_path: JSON.stringify([failingUrl, successUrl]),
      },
    });
    await runModuleScripts(id, coderEnvVars);

    const installLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/claude-code/install.log",
    );

    expect(installLog).toContain(failingUrl);
    expect(installLog).toContain(successUrl);
    expect(installLog).toContain(
      `Warning: Failed to fetch MCP configuration from '${failingUrl}'`,
    );
    expect(installLog).not.toContain(
      `Warning: Failed to fetch MCP configuration from '${successUrl}'`,
    );
    expect(installLog).toContain("claude mcp add-json --scope user");
  });

  test("no-extra-scripts-when-pre-post-unset", async () => {
    // When pre_install_script / post_install_script are not provided,
    // coder-utils must skip creating their coder_script resources. This
    // keeps the agent's scripts list clean in the Coder UI.
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install_claude_code: "false",
    });

    const scriptCount = state.resources
      .filter((r) => r.type === "coder_script")
      .reduce((n, r) => n + r.instances.length, 0);
    expect(scriptCount).toBe(1);

    const scripts = state.resources.filter((r) => r.type === "coder_script");
    const displayNames = scripts.flatMap((r) =>
      r.instances.map((i) =>
        getStringAttr(i.attributes as ResourceAttributes, "display_name"),
      ),
    );
    expect(displayNames).toEqual(["Claude Code: Install Script"]);
  });

  test("pre-post-install-scripts", async () => {
    const { id } = await setup({
      moduleVariables: {
        pre_install_script: "#!/bin/bash\necho 'claude-pre-install-script'",
        post_install_script: "#!/bin/bash\necho 'claude-post-install-script'",
      },
    });
    await runModuleScripts(id);

    const preInstallLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/claude-code/pre_install.log",
    );
    expect(preInstallLog).toContain("claude-pre-install-script");

    const postInstallLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/claude-code/post_install.log",
    );
    expect(postInstallLog).toContain("claude-post-install-script");
  });
});
