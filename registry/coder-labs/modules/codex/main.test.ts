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
    const key = `Codex: ${suffix}`;
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
  skipCodexMock?: boolean;
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
    install_codex: "false",
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
  if (!props?.skipCodexMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/codex",
      content: await Bun.file(
        path.join(moduleDir, "testdata", "codex-mock.sh"),
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
  const ordered: [string, string | undefined][] = [
    ["pre_install", scripts.pre_install],
    ["install", scripts.install],
    ["post_install", scripts.post_install],
  ];
  for (const [name, script] of ordered) {
    if (!script) continue;
    const target = `/tmp/coder-utils-${name}.sh`;
    await writeExecutable({
      containerId: id,
      filePath: target,
      content: script,
    });
    const resp = await execContainer(id, ["bash", "-c", `${envArgs}${target}`]);
    if (resp.exitCode !== 0) {
      console.log(`script ${name} failed:`);
      console.log(resp.stdout);
      console.log(resp.stderr);
      throw new Error(`coder-utils ${name} script exited ${resp.exitCode}`);
    }
  }
};

setDefaultTimeout(60 * 1000);

describe("codex", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const installLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder-labs/codex/logs/install.log",
    );
    expect(installLog).toContain("Skipping Codex installation");
  });

  test("install-codex-version", async () => {
    const version = "0.10.0";
    const { id, coderEnvVars, scripts } = await setup({
      skipCodexMock: true,
      moduleVariables: {
        install_codex: "true",
        codex_version: version,
      },
    });
    await runScripts(id, scripts, coderEnvVars);
    const installLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder-labs/codex/logs/install.log",
    );
    expect(installLog).toContain(version);
  });

  test("openai-api-key", async () => {
    const apiKey = "test-api-key-123";
    const { coderEnvVars } = await setup({
      moduleVariables: {
        openai_api_key: apiKey,
      },
    });
    expect(coderEnvVars["OPENAI_API_KEY"]).toBe(apiKey);
  });

  test("base-config-toml", async () => {
    const baseConfig = [
      'sandbox_mode = "danger-full-access"',
      'approval_policy = "never"',
      'preferred_auth_method = "apikey"',
      "",
      "[custom_section]",
      "new_feature = true",
    ].join("\n");
    const { id, scripts } = await setup({
      moduleVariables: {
        base_config_toml: baseConfig,
      },
    });
    await runScripts(id, scripts);
    const resp = await readFileContainer(id, "/home/coder/.codex/config.toml");
    expect(resp).toMatch(/sandbox_mode\s*=\s*['"]danger-full-access['"]/);
    expect(resp).toMatch(/preferred_auth_method\s*=\s*['"]apikey['"]/);
    expect(resp).toContain("[custom_section]");
  });

  test("additional-mcp-servers", async () => {
    const additional = [
      "[mcp_servers.GitHub]",
      'command = "npx"',
      'args = ["-y", "@modelcontextprotocol/server-github"]',
      'type = "stdio"',
      'description = "GitHub integration"',
    ].join("\n");
    const { id, scripts } = await setup({
      moduleVariables: {
        mcp: additional,
      },
    });
    await runScripts(id, scripts);
    const resp = await readFileContainer(id, "/home/coder/.codex/config.toml");
    expect(resp).toContain("[mcp_servers.GitHub]");
    expect(resp).toContain("GitHub integration");
  });

  test("minimal-default-config", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);
    const resp = await readFileContainer(id, "/home/coder/.codex/config.toml");
    expect(resp).toMatch(/preferred_auth_method\s*=\s*['"]apikey['"]/);
    expect(resp).not.toContain("model_provider");
    expect(resp).not.toContain("[model_providers.");
    expect(resp).not.toContain("model_reasoning_effort");
  });

  test("pre-post-install-scripts", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        pre_install_script: "#!/bin/bash\necho 'codex-pre-install-script'",
        post_install_script: "#!/bin/bash\necho 'codex-post-install-script'",
      },
    });
    await runScripts(id, scripts);

    const preInstallLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder-labs/codex/logs/pre_install.log",
    );
    expect(preInstallLog).toContain("codex-pre-install-script");

    const postInstallLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder-labs/codex/logs/post_install.log",
    );
    expect(postInstallLog).toContain("codex-post-install-script");
  });

  test("workdir-variable", async () => {
    const workdir = "/home/coder/codex-test-folder";
    const { id, scripts } = await setup({
      moduleVariables: {
        workdir,
      },
    });
    await runScripts(id, scripts);
    const installLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder-labs/codex/logs/install.log",
    );
    expect(installLog).toContain(workdir);
  });

  test("codex-with-ai-gateway", async () => {
    const { id, coderEnvVars, scripts } = await setup({
      moduleVariables: {
        enable_ai_gateway: "true",
        model_reasoning_effort: "none",
      },
    });
    await runScripts(id, scripts, coderEnvVars);
    const configToml = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    expect(configToml).toMatch(/model_provider\s*=\s*['"]aigateway['"]/);
    expect(configToml).toMatch(/model_reasoning_effort\s*=\s*['"]none['"]/);
    expect(configToml).toContain("[model_providers.aigateway]");
  });

  test("model-reasoning-effort-standalone", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        model_reasoning_effort: "high",
      },
    });
    await runScripts(id, scripts);
    const configToml = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    expect(configToml).toMatch(/model_reasoning_effort\s*=\s*['"]high['"]/);
    expect(configToml).not.toContain("model_provider");
  });

  test("workdir-trusted-project", async () => {
    const workdir = "/home/coder/trusted-project";
    const { id, scripts } = await setup({
      moduleVariables: {
        workdir,
      },
    });
    await runScripts(id, scripts);
    const configToml = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    expect(configToml).toMatch(
      new RegExp(`projects.*${workdir.replace(/\//g, "\\/")}.*`),
    );
    expect(configToml).toMatch(/trust_level\s*=\s*['"]trusted['"]/);
  });

  test("no-workdir-no-project-section", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        workdir: "",
      },
    });
    await runScripts(id, scripts);
    const configToml = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    expect(configToml).not.toContain("[projects.");
  });

  test("ai-gateway-with-custom-base-config", async () => {
    const baseConfig = [
      'sandbox_mode = "danger-full-access"',
      'model_provider = "aigateway"',
    ].join("\n");
    const { id, coderEnvVars, scripts } = await setup({
      moduleVariables: {
        enable_ai_gateway: "true",
        base_config_toml: baseConfig,
      },
    });
    await runScripts(id, scripts, coderEnvVars);
    const configToml = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    expect(configToml).toMatch(/model_provider\s*=\s*['"]aigateway['"]/);
    expect(configToml).toContain("[model_providers.aigateway]");
  });

  test("ai-gateway-custom-config-no-duplicate-provider", async () => {
    const baseConfig = [
      'model_provider = "aigateway"',
      "",
      "[model_providers.aigateway]",
      'name = "Custom AI Bridge"',
      'base_url = "https://custom.example.com"',
      'env_key = "CODER_AIBRIDGE_SESSION_TOKEN"',
      'wire_api = "responses"',
    ].join("\n");
    const { id, coderEnvVars, scripts } = await setup({
      moduleVariables: {
        enable_ai_gateway: "true",
        base_config_toml: baseConfig,
      },
    });
    await runScripts(id, scripts, coderEnvVars);
    const configToml = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    const matches = configToml.match(/\[model_providers\.aigateway\]/g) || [];
    expect(matches.length).toBe(1);
    expect(configToml).toContain("Custom AI Bridge");
  });

  test("install-codex-latest", async () => {
    const { id, coderEnvVars, scripts } = await setup({
      skipCodexMock: true,
      moduleVariables: {
        install_codex: "true",
      },
    });
    await runScripts(id, scripts, coderEnvVars);
    const installLog = await readFileContainer(
      id,
      "/home/coder/.coder-modules/coder-labs/codex/logs/install.log",
    );
    expect(installLog).toContain("Installed Codex CLI");
  });

  test("idempotent-defaults-preserve-user-edits", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);

    // User edits the config between restarts
    await execContainer(id, [
      "bash",
      "-c",
      `cat > /home/coder/.codex/config.toml << 'EOF'
preferred_auth_method = "login"
custom_user_key = "my_value"

[projects."/home/coder/project"]
trust_level = "trusted"
EOF`,
    ]);

    // Second run: user edits must survive
    await runScripts(id, scripts);
    const config = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    // User's overridden value preserved (not reset to "apikey")
    expect(config).toMatch(/preferred_auth_method\s*=\s*['"]login['"]/);
    // User's custom key preserved
    expect(config).toMatch(/custom_user_key\s*=\s*['"]my_value['"]/);
  });

  test("idempotent-mcp-deep-merge", async () => {
    const mcpConfig = [
      "[mcp_servers.github]",
      'command = "npx"',
      'args = ["-y", "@modelcontextprotocol/server-github"]',
      'type = "stdio"',
      "",
      "[mcp_servers.filesystem]",
      'command = "npx"',
      'args = ["-y", "@modelcontextprotocol/server-filesystem"]',
      'type = "stdio"',
    ].join("\n");
    const { id, scripts } = await setup({
      moduleVariables: { mcp: mcpConfig },
    });
    await runScripts(id, scripts);

    // User customizes the github MCP server between restarts
    await execContainer(id, [
      "bash",
      "-c",
      [
        "CONFIG=/home/coder/.codex/config.toml",
        // Replace the github command the user has customized
        "sed -i \"s/command = .npx./command = 'my-custom-npx'/\" $CONFIG",
      ].join(" && "),
    ]);

    // Second run
    await runScripts(id, scripts);
    const config = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    // User's customized github command preserved
    expect(config).toMatch(/command\s*=\s*['"]my-custom-npx['"]/);
    // filesystem server still present (not lost by shallow merge)
    expect(config).toContain("mcp_servers");
    expect(config).toContain("filesystem");
  });

  test("idempotent-base-config-preserves-user-edits", async () => {
    const baseConfig = [
      'sandbox_mode = "danger-full-access"',
      'preferred_auth_method = "apikey"',
    ].join("\n");
    const { id, scripts } = await setup({
      moduleVariables: { base_config_toml: baseConfig },
    });
    await runScripts(id, scripts);

    // User changes sandbox_mode
    await execContainer(id, [
      "bash",
      "-c",
      "sed -i 's/danger-full-access/sandbox/' /home/coder/.codex/config.toml",
    ]);

    // Second run
    await runScripts(id, scripts);
    const config = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    // User's change preserved
    expect(config).toMatch(/sandbox_mode\s*=\s*['"]sandbox['"]/);
    // Original key from base config still present
    expect(config).toContain("preferred_auth_method");
  });

  test("idempotent-run-twice-no-change", async () => {
    const { id, scripts } = await setup();

    // First run
    await runScripts(id, scripts);

    // Second run triggers a dasel roundtrip (quotes may change)
    await runScripts(id, scripts);
    const configAfterSecond = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );

    // Third run: if idempotent, output must be identical to second run
    await runScripts(id, scripts);
    const configAfterThird = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );

    // After the first roundtrip the serialization is stable, so a byte
    // comparison is valid from the second run onward.
    expect(configAfterThird).toEqual(configAfterSecond);
  });

  test("idempotent-mcp-new-servers-added-existing-kept", async () => {
    // First run: one MCP server
    const mcpRun1 = [
      "[mcp_servers.github]",
      'command = "npx"',
      'args = ["-y", "@modelcontextprotocol/server-github"]',
      'type = "stdio"',
    ].join("\n");
    const { id, scripts } = await setup({
      moduleVariables: { mcp: mcpRun1 },
    });
    await runScripts(id, scripts);

    // User adds their own MCP server manually
    await execContainer(id, [
      "bash",
      "-c",
      `cat >> /home/coder/.codex/config.toml << 'EOF'

[mcp_servers.custom]
command = "my-tool"
args = ["--serve"]
type = "stdio"
EOF`,
    ]);

    // Second run: same module config
    await runScripts(id, scripts);
    const config = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    // Module's github server still present
    expect(config).toContain("github");
    // User's manually-added custom server preserved
    expect(config).toMatch(/command\s*=\s*['"]my-tool['"]/);
  });

  test("idempotent-ai-gateway-preserves-user-provider", async () => {
    const { id, coderEnvVars, scripts } = await setup({
      moduleVariables: {
        enable_ai_gateway: "true",
      },
    });
    await runScripts(id, scripts, coderEnvVars);

    // User changes model_provider
    await execContainer(id, [
      "bash",
      "-c",
      "sed -i 's/model_provider = .*/model_provider = \"custom_provider\"/' /home/coder/.codex/config.toml",
    ]);

    // Second run
    await runScripts(id, scripts, coderEnvVars);
    const config = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    // User's custom provider survives
    expect(config).toMatch(/model_provider\s*=\s*['"]custom_provider['"]/);
  });

  test("base-config-plus-mcp-combined", async () => {
    const baseConfig = [
      'sandbox_mode = "danger-full-access"',
      'preferred_auth_method = "apikey"',
    ].join("\n");
    const mcpConfig = [
      "[mcp_servers.github]",
      'command = "npx"',
      'args = ["-y", "@modelcontextprotocol/server-github"]',
      'type = "stdio"',
    ].join("\n");
    const { id, scripts } = await setup({
      moduleVariables: {
        base_config_toml: baseConfig,
        mcp: mcpConfig,
      },
    });
    await runScripts(id, scripts);
    const config = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    // Base config keys present
    expect(config).toContain("sandbox_mode");
    expect(config).toContain("preferred_auth_method");
    // MCP server present
    expect(config).toContain("mcp_servers");
    expect(config).toContain("github");
  });

  test("all-config-sources-combined", async () => {
    const baseConfig = [
      'sandbox_mode = "danger-full-access"',
      'preferred_auth_method = "apikey"',
    ].join("\n");
    const mcpConfig = [
      "[mcp_servers.github]",
      'command = "npx"',
      'args = ["-y", "@modelcontextprotocol/server-github"]',
      'type = "stdio"',
    ].join("\n");
    const { id, coderEnvVars, scripts } = await setup({
      moduleVariables: {
        enable_ai_gateway: "true",
        base_config_toml: baseConfig,
        mcp: mcpConfig,
      },
    });
    await runScripts(id, scripts, coderEnvVars);
    const config = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    // Base config
    expect(config).toContain("sandbox_mode");
    expect(config).toContain("preferred_auth_method");
    // MCP
    expect(config).toContain("github");
    // AI gateway
    expect(config).toContain("model_providers");
  });

  test("idempotent-all-sources-user-edits-survive", async () => {
    const baseConfig = [
      'sandbox_mode = "danger-full-access"',
      'preferred_auth_method = "apikey"',
    ].join("\n");
    const mcpConfig = [
      "[mcp_servers.github]",
      'command = "npx"',
      'args = ["-y", "@modelcontextprotocol/server-github"]',
      'type = "stdio"',
    ].join("\n");
    const { id, coderEnvVars, scripts } = await setup({
      moduleVariables: {
        enable_ai_gateway: "true",
        base_config_toml: baseConfig,
        mcp: mcpConfig,
      },
    });
    await runScripts(id, scripts, coderEnvVars);

    // User edits multiple things
    await execContainer(id, [
      "bash",
      "-c",
      [
        "CONFIG=/home/coder/.codex/config.toml",
        // Change auth method
        "sed -i \"s/preferred_auth_method.*/preferred_auth_method = 'oauth'/\" $CONFIG",
        // Add a custom top-level key
        "echo 'user_note = \"do not touch\"' >> $CONFIG",
      ].join(" && "),
    ]);

    // Second run
    await runScripts(id, scripts, coderEnvVars);
    const config = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    // User edits survived
    expect(config).toMatch(/preferred_auth_method\s*=\s*['"]oauth['"]/);
    expect(config).toContain("user_note");
    // Module config still present
    expect(config).toContain("sandbox_mode");
    expect(config).toContain("github");
    expect(config).toContain("model_providers");
  });

  test("custom-config-drops-reasoning-effort", async () => {
    const baseConfig = [
      'sandbox_mode = "danger-full-access"',
      'preferred_auth_method = "apikey"',
    ].join("\n");
    const { id, scripts } = await setup({
      moduleVariables: {
        base_config_toml: baseConfig,
        model_reasoning_effort: "high",
      },
    });
    await runScripts(id, scripts);
    const configToml = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    expect(configToml).toMatch(/sandbox_mode\s*=\s*['"]danger-full-access['"]/);
    expect(configToml).not.toContain("model_reasoning_effort");
  });
});
