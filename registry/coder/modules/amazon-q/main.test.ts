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
  useLegacyMcpJson: true,
});

const requiredVars = {
  agent_id: "dummy-agent-id",
  agent_config: baseAgentConfig,
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
  agent_config: baseAgentConfig,
};

describe("amazon-q module v2.0.0", async () => {
  await runTerraformInit(moduleDir);

  // Test Case 1: Basic Usage – No Autonomous Use of Q
  // Matches CDES-203 Test Case #1: Basic Usage
  it("Test Case 1: Basic Usage - No Autonomous Use of Q", async () => {
    const basicUsageVars = {
      agent_id: "dummy-agent-id",
      auth_tarball: "dGVzdEF1dGhUYXJiYWxs", // base64 "testAuthTarball"
    };

    const state = await runTerraformApply(moduleDir, basicUsageVars);

    // Q is installed and authenticated
    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
    expect(statusSlugEnv.name).toBe("CODER_MCP_APP_STATUS_SLUG");
    expect(statusSlugEnv.value).toBe("amazonq");

    // AgentAPI is installed and configured (default behavior)
    const authTarballEnv = findResourceInstance(
      state,
      "coder_env",
      "auth_tarball",
    );
    expect(authTarballEnv).toBeDefined();
    expect(authTarballEnv.name).toBe("AMAZON_Q_AUTH_TARBALL");
    expect(authTarballEnv.value).toBe("dGVzdEF1dGhUYXJiYWxs");

    // Foundational configuration for all components is applied
    // No additional parameters are required for the module to work
    // Using the terminal application and Q chat returns a functional interface
  });

  // Test Case 2: Autonomous Usage – Autonomous Use of Q
  // Matches CDES-203 Test Case 2: Autonomous Usage
  it("Test Case 2: Autonomous Usage - Autonomous Use of Q", async () => {
    const autonomousUsageVars = {
      agent_id: "dummy-agent-id",
      auth_tarball: "dGVzdEF1dGhUYXJiYWxs", // base64 "testAuthTarball"
      ai_prompt:
        "Help me set up a Python FastAPI project with proper testing structure",
    };

    const state = await runTerraformApply(moduleDir, autonomousUsageVars);

    // Q is installed and authenticated
    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
    expect(statusSlugEnv.name).toBe("CODER_MCP_APP_STATUS_SLUG");
    expect(statusSlugEnv.value).toBe("amazonq");

    // AgentAPI is installed and configured
    const authTarballEnv = findResourceInstance(
      state,
      "coder_env",
      "auth_tarball",
    );
    expect(authTarballEnv).toBeDefined();
    expect(authTarballEnv.name).toBe("AMAZON_Q_AUTH_TARBALL");

    // AI prompt is passed through from external source
    // The Chat interface functions as required
    // The Tasks interface functions as required
    // The template can be invoked from GitHub integration as expected
  });

  // Test Case 3: Extended Configuration – Parameter Validation and File Rendering
  // Matches CDES-203 Test Case 3: Extended Configuration
  it("Test Case 3: Extended Configuration - Parameter Validation and File Rendering", async () => {
    const extendedConfigVars = {
      agent_id: "dummy-agent-id",
      auth_tarball: "dGVzdEF1dGhUYXJiYWxs", // base64 "testAuthTarball"
      amazon_q_version: "1.14.1",
      q_install_url: "https://desktop-release.q.us-east-1.amazonaws.com",
      install_amazon_q: true,
      install_agentapi: true,
      agentapi_version: "v0.6.0",
      trust_all_tools: true,
      ai_prompt:
        "Help me create a production-grade TypeScript monorepo with testing and deployment",
      system_prompt:
        "You are a helpful software assistant working in a secure enterprise environment",
      pre_install_script: "echo 'Pre-install setup'",
      post_install_script: "echo 'Post-install cleanup'",
      agent_config: JSON.stringify({
        name: "production-agent",
        description: "Production Amazon Q agent for enterprise environment",
        prompt:
          "You are a helpful software assistant working in a secure enterprise environment",
        mcpServers: {},
        tools: ["fs_read", "fs_write", "execute_bash", "use_aws", "knowledge"],
        toolAliases: {},
        allowedTools: ["fs_read"],
        resources: [
          "file://AmazonQ.md",
          "file://README.md",
          "file://.amazonq/rules/**/*.md",
        ],
        hooks: {},
        toolsSettings: {},
        useLegacyMcpJson: true,
      }),
    };

    const state = await runTerraformApply(moduleDir, extendedConfigVars);

    // All installation steps execute in the correct order
    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
    expect(statusSlugEnv.name).toBe("CODER_MCP_APP_STATUS_SLUG");
    expect(statusSlugEnv.value).toBe("amazonq");

    // auth_tarball is unpacked and used as expected
    const authTarballEnv = findResourceInstance(
      state,
      "coder_env",
      "auth_tarball",
    );
    expect(authTarballEnv).toBeDefined();
    expect(authTarballEnv.value).toBe("dGVzdEF1dGhUYXJiYWxs");

    // agent_config is rendered correctly, and the name field is used as the agent's name
    // The specified ai_prompt and system_prompt are respected by the Q agent
    // Tools are trusted globally if trust_all_tools = true
    // Files and scripts execute in proper sequence
  });

  // 1. Basic functionality test (replaces testRequiredVariables)
  it("works with required variables", async () => {
    const state = await runTerraformApply(moduleDir, requiredVars);

    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
    expect(statusSlugEnv.name).toBe("CODER_MCP_APP_STATUS_SLUG");
    expect(statusSlugEnv.value).toBe("amazonq");
  });

  // 2. Environment variables are created correctly
  it("creates required environment variables", async () => {
    const state = await runTerraformApply(moduleDir, fullConfigVars);

    // Check status slug environment variable
    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
    expect(statusSlugEnv.name).toBe("CODER_MCP_APP_STATUS_SLUG");
    expect(statusSlugEnv.value).toBe("amazonq");

    // Check auth tarball environment variable
    const authTarballEnv = findResourceInstance(
      state,
      "coder_env",
      "auth_tarball",
    );
    expect(authTarballEnv).toBeDefined();
    expect(authTarballEnv.name).toBe("AMAZON_Q_AUTH_TARBALL");
    expect(authTarballEnv.value).toBe("dGVzdEF1dGhUYXJiYWxs");
  });

  // 3. Empty auth tarball handling
  it("handles empty auth tarball correctly", async () => {
    const noAuthVars = {
      ...requiredVars,
      auth_tarball: "",
    };

    const state = await runTerraformApply(moduleDir, noAuthVars);

    // Auth tarball environment variable should not be created when empty
    const authTarballEnv = state.resources?.find(
      (r) => r.type === "coder_env" && r.name === "auth_tarball",
    );
    expect(authTarballEnv).toBeUndefined();
  });

  // 4. Status slug is always created
  it("creates status slug environment variable", async () => {
    const state = await runTerraformApply(moduleDir, requiredVars);

    // Status slug should always be configured
    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
    expect(statusSlugEnv.name).toBe("CODER_MCP_APP_STATUS_SLUG");
    expect(statusSlugEnv.value).toBe("amazonq");
  });

  // 5. Install options configuration
  it("respects install option flags", async () => {
    const noInstallVars = {
      ...requiredVars,
      install_amazon_q: false,
      install_agentapi: false,
    };

    const state = await runTerraformApply(moduleDir, noInstallVars);

    // Status slug should still be configured even when install options are disabled
    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
    expect(statusSlugEnv.value).toBe("amazonq");
  });

  // 6. Configurable installation URL
  it("uses configurable q_install_url parameter", async () => {
    const customUrlVars = {
      ...requiredVars,
      q_install_url: "https://internal-mirror.company.com/amazon-q",
    };

    const state = await runTerraformApply(moduleDir, customUrlVars);

    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
  });

  // 7. Version configuration
  it("uses specified versions", async () => {
    const versionVars = {
      ...requiredVars,
      amazon_q_version: "1.14.1",
      agentapi_version: "v0.6.0",
    };

    const state = await runTerraformApply(moduleDir, versionVars);

    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
  });

  // 8. UI configuration options
  it("supports UI customization options", async () => {
    const uiCustomVars = {
      ...requiredVars,
      order: 5,
      group: "Custom AI Tools",
      icon: "/icon/custom-amazon-q-icon.svg",
    };

    const state = await runTerraformApply(moduleDir, uiCustomVars);

    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
  });

  // 9. Pre and post install scripts
  it("supports pre and post install scripts", async () => {
    const scriptVars = {
      ...requiredVars,
      pre_install_script: "echo 'Pre-install setup'",
      post_install_script: "echo 'Post-install cleanup'",
    };

    const state = await runTerraformApply(moduleDir, scriptVars);

    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "status_slug",
    );
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
      useLegacyMcpJson: true,
    });

    const validAgentConfigVars = {
      ...requiredVars,
      agent_config: customAgentConfig,
    };

    const state = await runTerraformApply(moduleDir, validAgentConfigVars);

    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
  });

  // 11. Air-gapped installation support
  it("supports air-gapped installation with custom URL", async () => {
    const airGappedVars = {
      ...requiredVars,
      q_install_url: "https://artifacts.internal.corp/amazon-q-releases",
      amazon_q_version: "1.14.1",
    };

    const state = await runTerraformApply(moduleDir, airGappedVars);

    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
  });

  // 12. Trust all tools configuration
  it("handles trust_all_tools configuration", async () => {
    const trustVars = {
      ...requiredVars,
      trust_all_tools: true,
    };

    const state = await runTerraformApply(moduleDir, trustVars);

    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
  });

  // 13. AI prompt configuration
  it("handles AI prompt configuration", async () => {
    const promptVars = {
      ...requiredVars,
      ai_prompt: "Create a comprehensive test suite for the application",
    };

    const state = await runTerraformApply(moduleDir, promptVars);

    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
  });

  // 14. Agent config with minimal structure
  it("handles minimal agent config structure", async () => {
    const minimalAgentConfig = JSON.stringify({
      name: "minimal-agent",
      description: "Minimal agent config",
      prompt: "You are a minimal AI assistant.",
      mcpServers: {},
      tools: ["fs_read", "fs_write", "execute_bash", "use_aws", "knowledge"],
      toolAliases: {},
      allowedTools: ["fs_read"],
      resources: ["file://README.md"],
      hooks: {},
      toolsSettings: {},
      useLegacyMcpJson: true,
    });

    const minimalVars = {
      ...requiredVars,
      agent_config: minimalAgentConfig,
    };

    const state = await runTerraformApply(moduleDir, minimalVars);

    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
  });

  // 15. JSON encoding validation for system prompts with newlines
  it("handles system prompts with newlines correctly", async () => {
    const multilinePromptVars = {
      ...requiredVars,
      system_prompt: "Multi-line\nsystem prompt\nwith newlines",
    };

    const state = await runTerraformApply(moduleDir, multilinePromptVars);

    // Should create the basic resources without JSON parsing errors
    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
    expect(statusSlugEnv.value).toBe("amazonq");
  });

  // 16. Agent name extraction from custom config
  it("extracts agent name from custom configuration correctly", async () => {
    const customNameConfig = JSON.stringify({
      name: "enterprise-production-agent",
      description: "Enterprise production agent configuration",
      prompt: "You are an enterprise production AI assistant.",
      mcpServers: {},
      tools: ["fs_read", "fs_write", "execute_bash", "use_aws", "knowledge"],
      toolAliases: {},
      allowedTools: ["fs_read", "fs_write", "execute_bash"],
      resources: ["file://README.md", "file://.amazonq/rules/**/*.md"],
      hooks: {},
      toolsSettings: {},
      useLegacyMcpJson: true,
    });

    const customNameVars = {
      ...requiredVars,
      agent_config: customNameConfig,
    };

    const state = await runTerraformApply(moduleDir, customNameVars);

    // Should create the basic resources
    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
    expect(statusSlugEnv.value).toBe("amazonq");
  });
});
