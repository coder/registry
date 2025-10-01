import { describe, it, expect } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  findResourceInstance,
} from "~test";
import path from "path";

const moduleDir = path.resolve(__dirname);

const requiredVars = {
  agent_id: "test-agent-id",
  workdir: "/home/coder",
  external_auth_id: "github",
};

const fullConfigVars = {
  agent_id: "test-agent-id",
  workdir: "/home/coder",
  external_auth_id: "github",
  copilot_model: "claude-sonnet-4.5",
  report_tasks: true,
  order: 1,
  group: "AI Tools",
  icon: "/icon/custom-copilot.svg",
  pre_install_script: "echo 'Starting pre-install'",
  post_install_script: "echo 'Completed post-install'",
  copilot_config: JSON.stringify({
    banner: "auto",
    theme: "light",
    trusted_folders: ["/home/coder", "/workspace"],
  }),
  mcp_config: JSON.stringify({
    mcpServers: {
      github: {
        command: "@github/copilot-mcp-github",
        env: {
          GITHUB_TOKEN: "${GITHUB_TOKEN}",
        },
      },
      custom: {
        command: "custom-server",
        args: ["--config", "custom.json"],
      },
    },
  }),
  trusted_directories: '["/workspace", "/projects"]',
  allow_tools: '["fs_read", "fs_write"]',
  deny_tools: '["execute_bash"]',
};

describe("copilot-cli module", async () => {
  await runTerraformInit(moduleDir);

  it("works with required variables", async () => {
    const state = await runTerraformApply(moduleDir, requiredVars);

    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "mcp_app_status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
    expect(statusSlugEnv.name).toBe("CODER_MCP_APP_STATUS_SLUG");
    expect(statusSlugEnv.value).toBe("copilot-cli");
  });

  it("creates required environment variables", async () => {
    const state = await runTerraformApply(moduleDir, fullConfigVars);

    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "mcp_app_status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
    expect(statusSlugEnv.name).toBe("CODER_MCP_APP_STATUS_SLUG");
    expect(statusSlugEnv.value).toBe("copilot-cli");
  });

  it("uses default model when not specified", async () => {
    const state = await runTerraformApply(moduleDir, requiredVars);

    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "mcp_app_status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
  });

  it("supports custom copilot model", async () => {
    const customModelVars = {
      ...requiredVars,
      copilot_model: "claude-sonnet-4.5",
    };

    const state = await runTerraformApply(moduleDir, customModelVars);

    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "mcp_app_status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
  });

  it("supports custom copilot configuration", async () => {
    const customConfigVars = {
      ...requiredVars,
      copilot_config: JSON.stringify({
        banner: "auto",
        theme: "dark",
        trusted_folders: ["/home/coder", "/workspace"],
      }),
    };

    const state = await runTerraformApply(moduleDir, customConfigVars);

    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "mcp_app_status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
  });

  it("supports trusted directories", async () => {
    const trustedDirsVars = {
      ...requiredVars,
      trusted_directories: '["/workspace", "/projects", "/data"]',
    };

    const state = await runTerraformApply(moduleDir, trustedDirsVars);

    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "mcp_app_status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
  });

  it("supports custom MCP configuration", async () => {
    const mcpConfigVars = {
      ...requiredVars,
      mcp_config: JSON.stringify({
        mcpServers: {
          filesystem: {
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-filesystem", "/tmp"],
          },
          github: {
            command: "@github/copilot-mcp-github",
            env: {
              GITHUB_TOKEN: "${GITHUB_TOKEN}",
            },
          },
        },
      }),
    };

    const state = await runTerraformApply(moduleDir, mcpConfigVars);

    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "mcp_app_status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
  });

  it("supports tool permissions", async () => {
    const toolPermissionsVars = {
      ...requiredVars,
      allow_tools: '["fs_read", "fs_write", "execute_bash"]',
      deny_tools: '["rm", "sudo"]',
    };

    const state = await runTerraformApply(moduleDir, toolPermissionsVars);

    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "mcp_app_status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
  });

  it("supports UI customization options", async () => {
    const uiCustomVars = {
      ...requiredVars,
      order: 5,
      group: "Custom AI Tools",
      icon: "/icon/custom-copilot-icon.svg",
    };

    const state = await runTerraformApply(moduleDir, uiCustomVars);

    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "mcp_app_status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
  });

  it("supports pre and post install scripts", async () => {
    const scriptVars = {
      ...requiredVars,
      pre_install_script: "echo 'Pre-install setup for Copilot CLI'",
      post_install_script: "echo 'Post-install cleanup for Copilot CLI'",
    };

    const state = await runTerraformApply(moduleDir, scriptVars);

    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "mcp_app_status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
  });

  it("handles task reporting disabled", async () => {
    const noReportingVars = {
      ...requiredVars,
      report_tasks: false,
    };

    const state = await runTerraformApply(moduleDir, noReportingVars);

    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "mcp_app_status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
    expect(statusSlugEnv.value).toBe("copilot-cli");
  });

  it("supports external auth configuration", async () => {
    const customAuthVars = {
      ...requiredVars,
      external_auth_id: "custom-github",
    };

    const state = await runTerraformApply(moduleDir, customAuthVars);

    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "mcp_app_status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
  });

  it("supports system prompt configuration", async () => {
    const systemPromptVars = {
      ...requiredVars,
      system_prompt:
        "You are a helpful AI assistant that focuses on code quality and best practices.",
    };

    const state = await runTerraformApply(moduleDir, systemPromptVars);

    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "mcp_app_status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
  });

  it("works with full configuration", async () => {
    const state = await runTerraformApply(moduleDir, fullConfigVars);

    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "mcp_app_status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
    expect(statusSlugEnv.name).toBe("CODER_MCP_APP_STATUS_SLUG");
    expect(statusSlugEnv.value).toBe("copilot-cli");
  });

  it("supports github_token variable", async () => {
    const tokenVars = {
      ...requiredVars,
      github_token: "test_github_token_123",
    };

    const state = await runTerraformApply(moduleDir, tokenVars);

    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "mcp_app_status_slug",
    );
    expect(statusSlugEnv).toBeDefined();

    const githubTokenEnv = findResourceInstance(
      state,
      "coder_env",
      "github_token",
    );
    expect(githubTokenEnv).toBeDefined();
    expect(githubTokenEnv.name).toBe("GITHUB_TOKEN");
    expect(githubTokenEnv.value).toBe("test_github_token_123");
  });

  it("supports resume session configuration", async () => {
    const resumeSessionVars = {
      ...requiredVars,
      resume_session: false,
    };

    const state = await runTerraformApply(moduleDir, resumeSessionVars);

    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "mcp_app_status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
  });
});
