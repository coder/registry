import { describe, expect, it } from "bun:test";
import {
  findResourceInstance,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("copilot-cli", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "test-agent",
    workdir: "/home/coder",
  });

  it("creates mcp_app_status_slug env var", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      workdir: "/home/coder",
    });

    const statusSlugEnv = findResourceInstance(
      state,
      "coder_env",
      "mcp_app_status_slug",
    );
    expect(statusSlugEnv).toBeDefined();
    expect(statusSlugEnv.name).toBe("CODER_MCP_APP_STATUS_SLUG");
    expect(statusSlugEnv.value).toBe("copilot-cli");
  });

  it("creates github_token env var with correct value", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      workdir: "/home/coder",
      github_token: "test_token_12345",
    });

    const githubTokenEnv = findResourceInstance(
      state,
      "coder_env",
      "github_token",
    );
    expect(githubTokenEnv).toBeDefined();
    expect(githubTokenEnv.name).toBe("GITHUB_TOKEN");
    expect(githubTokenEnv.value).toBe("test_token_12345");
  });

  it("does not create github_token env var when empty", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      workdir: "/home/coder",
      github_token: "",
    });

    const githubTokenEnvs = state.resources.filter(
      (r) => r.type === "coder_env" && r.name === "github_token",
    );
    expect(githubTokenEnvs.length).toBe(0);
  });

  it("creates copilot_model env var for non-default models", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      workdir: "/home/coder",
      copilot_model: "claude-sonnet-4.5",
    });

    const modelEnv = findResourceInstance(state, "coder_env", "copilot_model");
    expect(modelEnv).toBeDefined();
    expect(modelEnv.name).toBe("COPILOT_MODEL");
    expect(modelEnv.value).toBe("claude-sonnet-4.5");
  });

  it("does not create copilot_model env var for default model", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      workdir: "/home/coder",
      copilot_model: "claude-sonnet-4.5",
    });

    const modelEnvs = state.resources.filter(
      (r) => r.type === "coder_env" && r.name === "copilot_model",
    );
    expect(modelEnvs.length).toBe(0);
  });

  it("creates coder_script resources via agentapi module", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      workdir: "/home/coder",
    });

    // The agentapi module should create coder_script resources for install and start
    const scripts = state.resources.filter((r) => r.type === "coder_script");
    expect(scripts.length).toBeGreaterThan(0);
  });

  it("validates copilot_model accepts valid values", async () => {
    // Test valid models don't throw errors
    await expect(
      runTerraformApply(import.meta.dir, {
        agent_id: "test-agent",
        workdir: "/home/coder",
        copilot_model: "gpt-5",
      }),
    ).resolves.toBeDefined();

    await expect(
      runTerraformApply(import.meta.dir, {
        agent_id: "test-agent",
        workdir: "/home/coder",
        copilot_model: "claude-sonnet-4.5",
      }),
    ).resolves.toBeDefined();
  });
});
