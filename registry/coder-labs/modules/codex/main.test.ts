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

const MANAGED_START = "# >>> coder-managed: codex module >>>";
const MANAGED_END = "# <<< coder-managed: codex module <<<";

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
    const version = "0.134.0";
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
    expect(resp).toContain(MANAGED_START);
    expect(resp).toContain(MANAGED_END);
    expect(resp).toMatch(/sandbox_mode\s*=\s*"danger-full-access"/);
    expect(resp).toMatch(/preferred_auth_method\s*=\s*"apikey"/);
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
    expect(resp).toContain(MANAGED_START);
    expect(resp).toContain(MANAGED_END);
    expect(resp).toMatch(/preferred_auth_method\s*=\s*"apikey"/);
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
    expect(configToml).toMatch(/model_provider\s*=\s*"aigateway"/);
    expect(configToml).toMatch(/model_reasoning_effort\s*=\s*"none"/);
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
    expect(configToml).toMatch(/model_reasoning_effort\s*=\s*"high"/);
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
    expect(configToml).toMatch(new RegExp(`\\[projects\\..*${workdir}.*\\]`));
    expect(configToml).toMatch(/trust_level\s*=\s*"trusted"/);
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
    expect(configToml).toMatch(/model_provider\s*=\s*"aigateway"/);
    expect(configToml).toContain("[model_providers.aigateway]");
  });

  test("ai-gateway-custom-config-no-duplicate-provider", async () => {
    const baseConfig = [
      'model_provider = "aigateway"',
      "",
      "[model_providers.aigateway]",
      'name = "Custom AI Bridge"',
      'base_url = "https://custom.example.com"',
      'env_key = "OPENAI_CODER_AIGATEWAY_SESSION_TOKEN"',
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
    expect(config).toMatch(/sandbox_mode\s*=\s*"danger-full-access"/);
    expect(config).toMatch(/preferred_auth_method\s*=\s*"apikey"/);
    expect(config).toContain("mcp_servers");
    expect(config).toMatch(/command\s*=\s*"npx"/);
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
    expect(config).toMatch(/sandbox_mode\s*=\s*"danger-full-access"/);
    expect(config).toMatch(/preferred_auth_method\s*=\s*"apikey"/);
    expect(config).toMatch(/command\s*=\s*"npx"/);
    expect(config).toContain("[model_providers.aigateway]");
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
    expect(configToml).toMatch(/sandbox_mode\s*=\s*"danger-full-access"/);
    expect(configToml).not.toContain("model_reasoning_effort");
  });

  // --- idempotency tests: marker-block semantics ---

  test("idempotent-user-section-survives-restart", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);

    // User adds a custom section after the managed block.
    await execContainer(id, [
      "bash",
      "-c",
      `cat >> /home/coder/.codex/config.toml << 'EOF'

[mcp_servers.user_tool]
command = "my-tool"
args = ["--serve"]
type = "stdio"
EOF`,
    ]);

    // Second run: managed block is regenerated, user section survives.
    await runScripts(id, scripts);
    const config = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    // Managed content still present
    expect(config).toMatch(/preferred_auth_method\s*=\s*"apikey"/);
    expect(config).toContain(MANAGED_START);
    expect(config).toContain(MANAGED_END);
    // User section preserved
    expect(config).toContain("[mcp_servers.user_tool]");
    expect(config).toMatch(/command\s*=\s*"my-tool"/);
    // User section must appear after the managed block, not inside or before it.
    const endIdx = config.indexOf(MANAGED_END);
    const sectionIdx = config.indexOf("[mcp_servers.user_tool]");
    expect(sectionIdx).toBeGreaterThan(endIdx);
  });

  test("idempotent-user-bare-keys-stay-at-root-scope", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);

    // User prepends bare keys before the managed block and appends a section after it.
    await execContainer(id, [
      "bash",
      "-c",
      `config=/home/coder/.codex/config.toml
{ printf 'my_custom_key = "hello"\\nsandbox_mode = "full"\\n\\n'; cat "$config"; } > /tmp/codex_c.toml && mv /tmp/codex_c.toml "$config"
cat >> "$config" << 'EOF'

[mcp_servers.user_tool]
command = "my-tool"
EOF`,
    ]);

    // Second run
    await runScripts(id, scripts);
    const config = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );

    // Bare keys placed before the managed block must remain before MANAGED_START.
    const startIdx = config.indexOf(MANAGED_START);
    const customKeyIdx = config.indexOf('my_custom_key = "hello"');
    const sandboxIdx = config.indexOf('sandbox_mode = "full"');
    expect(customKeyIdx).toBeGreaterThan(-1);
    expect(sandboxIdx).toBeGreaterThan(-1);
    expect(customKeyIdx).toBeLessThan(startIdx);
    expect(sandboxIdx).toBeLessThan(startIdx);

    // Section appended after the managed block must remain after MANAGED_END.
    const endIdx = config.indexOf(MANAGED_END);
    const sectionIdx = config.indexOf("[mcp_servers.user_tool]");
    expect(sectionIdx).toBeGreaterThan(endIdx);
  });

  test("idempotent-managed-block-regenerated", async () => {
    const { id, scripts } = await setup({
      moduleVariables: {
        model_reasoning_effort: "high",
      },
    });
    await runScripts(id, scripts);

    // User modifies a value inside the managed block.
    await execContainer(id, [
      "bash",
      "-c",
      "sed -i 's/model_reasoning_effort.*/model_reasoning_effort = \"low\"/' /home/coder/.codex/config.toml",
    ]);

    // Verify user edit took effect.
    const edited = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    expect(edited).toMatch(/model_reasoning_effort\s*=\s*"low"/);

    // Second run: managed block is regenerated with original values.
    await runScripts(id, scripts);
    const config = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    // Original managed value restored
    expect(config).toMatch(/model_reasoning_effort\s*=\s*"high"/);
    expect(config).not.toMatch(/model_reasoning_effort\s*=\s*"low"/);
  });

  test("idempotent-user-comments-preserved", async () => {
    const { id, scripts } = await setup();
    await runScripts(id, scripts);

    // User adds a bare-key comment, a bare key, then a section with comments.
    await execContainer(id, [
      "bash",
      "-c",
      `cat >> /home/coder/.codex/config.toml << 'EOF'

# My personal top-level setting
my_flag = true

# My personal MCP server
[mcp_servers.notes]
command = "notes-server"
# This server is for my personal notes
type = "stdio"
EOF`,
    ]);

    // Second run
    await runScripts(id, scripts);
    const config = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    // Bare-key comment preserved in output
    expect(config).toContain("# My personal top-level setting");
    // Section comments preserved below managed block
    expect(config).toContain("# My personal MCP server");
    expect(config).toContain("# This server is for my personal notes");
    expect(config).toContain("[mcp_servers.notes]");
  });

  test("idempotent-stable-after-roundtrip", async () => {
    const { id, scripts } = await setup();

    // First run: write the managed block.
    await runScripts(id, scripts);

    // User appends content outside the managed block.
    await execContainer(id, [
      "bash",
      "-c",
      `cat >> /home/coder/.codex/config.toml << 'EOF'

roundtrip_key = "present"

# User's personal server
[mcp_servers.roundtrip]
command = "roundtrip-tool"
type = "stdio"
EOF`,
    ]);

    // Second run: managed block is regenerated with user content in place.
    await runScripts(id, scripts);
    const configAfterSecond = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );

    // Third run: output must be byte-identical (no double-hoisting or newline drift).
    await runScripts(id, scripts);
    const configAfterThird = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );

    expect(configAfterThird).toEqual(configAfterSecond);
    expect(configAfterThird).toContain('roundtrip_key = "present"');
    expect(configAfterThird).toContain("[mcp_servers.roundtrip]");
  });

  test("idempotent-mcp-new-servers-added-existing-kept", async () => {
    const mcpConfig = [
      "[mcp_servers.github]",
      'command = "npx"',
      'args = ["-y", "@modelcontextprotocol/server-github"]',
      'type = "stdio"',
    ].join("\n");
    const { id, scripts } = await setup({
      moduleVariables: { mcp: mcpConfig },
    });
    await runScripts(id, scripts);

    // User adds their own MCP server after the managed block.
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

    // Second run
    await runScripts(id, scripts);
    const config = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    // Module's github server still present (in managed block)
    expect(config).toContain("[mcp_servers.github]");
    expect(config).toMatch(/command\s*=\s*"npx"/);
    // User's custom server preserved (outside managed block)
    expect(config).toContain("[mcp_servers.custom]");
    expect(config).toMatch(/command\s*=\s*"my-tool"/);
  });

  test("no-markers-first-run-overwrites", async () => {
    const { id, scripts } = await setup();

    // Simulate a legacy config without markers (pre-upgrade).
    await execContainer(id, [
      "bash",
      "-c",
      `mkdir -p /home/coder/.codex && cat > /home/coder/.codex/config.toml << 'EOF'
preferred_auth_method = "login"
legacy_key = "old_value"

[mcp_servers.legacy]
command = "legacy-tool"
type = "stdio"
EOF`,
    ]);

    // First run: no markers found, file is overwritten entirely by the managed block.
    await runScripts(id, scripts);
    const config = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    // Managed block is written
    expect(config).toContain(MANAGED_START);
    expect(config).toContain(MANAGED_END);
    // Legacy content is gone
    expect(config).not.toContain('preferred_auth_method = "login"');
    expect(config).not.toContain('legacy_key = "old_value"');
    expect(config).not.toContain("[mcp_servers.legacy]");

    // Second run: output must be stable.
    await runScripts(id, scripts);
    const configAfterSecond = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    expect(configAfterSecond).toEqual(config);
  });

  test("idempotent-all-sources-user-content-survives", async () => {
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

    // User adds content outside the managed block.
    await execContainer(id, [
      "bash",
      "-c",
      `cat >> /home/coder/.codex/config.toml << 'EOF'

# User's personal MCP server
[mcp_servers.personal]
command = "personal-server"
type = "stdio"
EOF`,
    ]);

    // Second run
    await runScripts(id, scripts, coderEnvVars);
    const config = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );
    // All managed content correct
    expect(config).toMatch(/sandbox_mode\s*=\s*"danger-full-access"/);
    expect(config).toMatch(/preferred_auth_method\s*=\s*"apikey"/);
    expect(config).toContain("[mcp_servers.github]");
    expect(config).toContain("[model_providers.aigateway]");
    // User content preserved
    expect(config).toContain("# User's personal MCP server");
    expect(config).toContain("[mcp_servers.personal]");
    expect(config).toMatch(/command\s*=\s*"personal-server"/);
  });

  test("idempotent-multiple-restarts-user-content-stable", async () => {
    const mcpConfig = [
      "[mcp_servers.github]",
      'command = "npx"',
      'args = ["-y", "@modelcontextprotocol/server-github"]',
      'type = "stdio"',
    ].join("\n");
    const { id, scripts } = await setup({
      moduleVariables: { mcp: mcpConfig },
    });
    await runScripts(id, scripts);

    // User adds content outside managed block.
    await execContainer(id, [
      "bash",
      "-c",
      `cat >> /home/coder/.codex/config.toml << 'EOF'

# User customizations
[mcp_servers.custom]
command = "custom-tool"
type = "stdio"
EOF`,
    ]);

    // Run 2
    await runScripts(id, scripts);
    const configAfterSecond = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );

    // Run 3: should be byte-identical to run 2
    await runScripts(id, scripts);
    const configAfterThird = await readFileContainer(
      id,
      "/home/coder/.codex/config.toml",
    );

    expect(configAfterThird).toEqual(configAfterSecond);
    // User content still present
    expect(configAfterThird).toContain("# User customizations");
    expect(configAfterThird).toContain("[mcp_servers.custom]");
  });
});
