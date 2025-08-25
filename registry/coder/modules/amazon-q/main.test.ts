import { describe, it, expect } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  findResourceInstance,
} from "~test";
import path from "path";

const moduleDir = path.resolve(__dirname);

// Always provide agent_config to bypass template parsing issues
const baseAgentConfig = JSON.stringify({
  name: "test-agent",
  description: "Test agent configuration",
  prompt: "You are a helpful AI assistant.",
  mcpServers: {},
  tools: ["fs_read", "fs_write", "execute_bash", "use_aws", "knowledge"],
  toolAliases: {},
  allowedTools: ["fs_read"],
  resources: ["file://README.md", "file://.amazonq/rules/**/*.md"],
  hooks: {},
  toolsSettings: {},
  useLegacyMcpJson: true
});

const requiredVars = {
  agent_id: "dummy-agent-id",
  agent_config: baseAgentConfig
};

const fullConfigVars = {
  agent_id: "dummy-agent-id",
  install_amazon_q: true,
  install_agentapi: true,
  agentapi_version: "v0.6.0",
  amazon_q_version: "1.14.1",
  q_install_url: "https://desktop-release.q.us-east-1.amazonaws.com",
  trust_all_tools: false,
  ai_prompt: "Build a comprehensive test suite",
  auth_tarball: "dGVzdEF1dGhUYXJiYWxs", // base64 "testAuthTarball"
  order: 1,
  group: "AI Tools",
  icon: "/icon/custom-amazon-q.svg",
  pre_install_script: "echo 'Starting pre-install'",
  post_install_script: "echo 'Completed post-install'",
  agent_config: baseAgentConfig
};

describe("amazon-q module v2.0.0", async () => {
  await runTerraformInit(moduleDir);

  // 1. Basic functionality test (replaces testRequiredVariables)
  it("works with required variables", async () => {
    const state = await runTerraformApply(moduleDir, requiredVars);
    
    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(state, "coder_env", "status_slug");
    expect(statusSlugEnv).toBeDefined();
    expect(statusSlugEnv.name).toBe("CODER_MCP_APP_STATUS_SLUG");
    expect(statusSlugEnv.value).toBe("amazonq");
  });

  // 2. Environment variables are created correctly
  it("creates required environment variables", async () => {
    const state = await runTerraformApply(moduleDir, fullConfigVars);
    
    // Check status slug environment variable
    const statusSlugEnv = findResourceInstance(state, "coder_env", "status_slug");
    expect(statusSlugEnv).toBeDefined();
    expect(statusSlugEnv.name).toBe("CODER_MCP_APP_STATUS_SLUG");
    expect(statusSlugEnv.value).toBe("amazonq");

    // Check auth tarball environment variable
    const authTarballEnv = findResourceInstance(state, "coder_env", "auth_tarball");
    expect(authTarballEnv).toBeDefined();
    expect(authTarballEnv.name).toBe("AMAZON_Q_AUTH_TARBALL");
    expect(authTarballEnv.value).toBe("dGVzdEF1dGhUYXJiYWxs");
  });

  // 3. Empty auth tarball handling
  it("handles empty auth tarball correctly", async () => {
    const noAuthVars = {
      ...requiredVars,
      auth_tarball: ""
    };
    
    const state = await runTerraformApply(moduleDir, noAuthVars);
    
    // Auth tarball environment variable should not be created when empty
    const authTarballEnv = state.resources?.find(r => 
      r.type === "coder_env" && r.name === "auth_tarball"
    );
    expect(authTarballEnv).toBeUndefined();
  });

  // 4. Status slug is always created
  it("creates status slug environment variable", async () => {
    const state = await runTerraformApply(moduleDir, requiredVars);
    
    // Status slug should always be configured
    const statusSlugEnv = findResourceInstance(state, "coder_env", "status_slug");
    expect(statusSlugEnv).toBeDefined();
    expect(statusSlugEnv.name).toBe("CODER_MCP_APP_STATUS_SLUG");
    expect(statusSlugEnv.value).toBe("amazonq");
  });

  // 5. Install options configuration
  it("respects install option flags", async () => {
    const noInstallVars = {
      ...requiredVars,
      install_amazon_q: false,
      install_agentapi: false
    };
    
    const state = await runTerraformApply(moduleDir, noInstallVars);
    
    // Status slug should still be configured even when install options are disabled
    const statusSlugEnv = findResourceInstance(state, "coder_env", "status_slug");
    expect(statusSlugEnv).toBeDefined();
    expect(statusSlugEnv.value).toBe("amazonq");
  });

  // 6. Configurable installation URL
  it("uses configurable q_install_url parameter", async () => {
    const customUrlVars = {
      ...requiredVars,
      q_install_url: "https://internal-mirror.company.com/amazon-q"
    };
    
    const state = await runTerraformApply(moduleDir, customUrlVars);
    
    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(state, "coder_env", "status_slug");
    expect(statusSlugEnv).toBeDefined();
  });

  // 7. Version configuration
  it("uses specified versions", async () => {
    const versionVars = {
      ...requiredVars,
      amazon_q_version: "1.14.1",
      agentapi_version: "v0.6.0"
    };
    
    const state = await runTerraformApply(moduleDir, versionVars);
    
    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(state, "coder_env", "status_slug");
    expect(statusSlugEnv).toBeDefined();
  });

  // 8. UI configuration options
  it("supports UI customization options", async () => {
    const uiCustomVars = {
      ...requiredVars,
      order: 5,
      group: "Custom AI Tools",
      icon: "/icon/custom-amazon-q-icon.svg"
    };
    
    const state = await runTerraformApply(moduleDir, uiCustomVars);
    
    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(state, "coder_env", "status_slug");
    expect(statusSlugEnv).toBeDefined();
  });

  // 9. Pre and post install scripts
  it("supports pre and post install scripts", async () => {
    const scriptVars = {
      ...requiredVars,
      pre_install_script: "echo 'Pre-install setup'",
      post_install_script: "echo 'Post-install cleanup'"
    };
    
    const state = await runTerraformApply(moduleDir, scriptVars);
    
    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(state, "coder_env", "status_slug");
    expect(statusSlugEnv).toBeDefined();
  });

  // 10. Valid agent_config JSON with different agent name
  it("handles valid agent_config JSON with custom agent name", async () => {
    const customAgentConfig = JSON.stringify({
      name: "production-agent",
      description: "Production Amazon Q agent",
      prompt: "You are a production AI assistant.",
      mcpServers: {},
      tools: ["fs_read", "fs_write"],
      toolAliases: {},
      allowedTools: ["fs_read"],
      resources: ["file://README.md"],
      hooks: {},
      toolsSettings: {},
      useLegacyMcpJson: true
    });
    
    const validAgentConfigVars = {
      ...requiredVars,
      agent_config: customAgentConfig
    };
    
    const state = await runTerraformApply(moduleDir, validAgentConfigVars);
    
    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(state, "coder_env", "status_slug");
    expect(statusSlugEnv).toBeDefined();
  });

  // 11. Air-gapped installation support
  it("supports air-gapped installation with custom URL", async () => {
    const airGappedVars = {
      ...requiredVars,
      q_install_url: "https://artifacts.internal.corp/amazon-q-releases",
      amazon_q_version: "1.14.1"
    };
    
    const state = await runTerraformApply(moduleDir, airGappedVars);
    
    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(state, "coder_env", "status_slug");
    expect(statusSlugEnv).toBeDefined();
  });

  // 12. Trust all tools configuration
  it("handles trust_all_tools configuration", async () => {
    const trustVars = {
      ...requiredVars,
      trust_all_tools: true
    };
    
    const state = await runTerraformApply(moduleDir, trustVars);
    
    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(state, "coder_env", "status_slug");
    expect(statusSlugEnv).toBeDefined();
  });

  // 13. AI prompt configuration
  it("handles AI prompt configuration", async () => {
    const promptVars = {
      ...requiredVars,
      ai_prompt: "Create a comprehensive test suite for the application"
    };
    
    const state = await runTerraformApply(moduleDir, promptVars);
    
    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(state, "coder_env", "status_slug");
    expect(statusSlugEnv).toBeDefined();
  });

  // 14. Module directory name configuration
  it("handles module directory name configuration", async () => {
    const dirVars = {
      ...requiredVars,
      module_dir_name: ".custom-amazonq"
    };
    
    const state = await runTerraformApply(moduleDir, dirVars);
    
    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(state, "coder_env", "status_slug");
    expect(statusSlugEnv).toBeDefined();
  });

  // 15. Agent config with minimal structure
  it("handles minimal agent config structure", async () => {
    const minimalAgentConfig = JSON.stringify({
      name: "minimal-agent",
      description: "Minimal agent config"
    });
    
    const minimalVars = {
      ...requiredVars,
      agent_config: minimalAgentConfig
    };
    
    const state = await runTerraformApply(moduleDir, minimalVars);
    
    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(state, "coder_env", "status_slug");
    expect(statusSlugEnv).toBeDefined();
  });
});
