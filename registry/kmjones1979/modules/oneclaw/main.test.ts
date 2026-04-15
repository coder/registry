import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  findResourceInstance,
} from "~test";

describe("oneclaw", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "test-agent",
  });

  it("manual mode sets env vars and mcp script", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      vault_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      api_token: "ocv_testtoken",
    });

    const vaultEnv = findResourceInstance(
      state,
      "coder_env",
      "oneclaw_vault_id",
    );
    expect(vaultEnv.name).toBe("ONECLAW_VAULT_ID");

    const apiKeyEnv = findResourceInstance(
      state,
      "coder_env",
      "oneclaw_agent_api_key",
    );
    expect(apiKeyEnv.name).toBe("ONECLAW_AGENT_API_KEY");

    const baseUrlEnv = findResourceInstance(
      state,
      "coder_env",
      "oneclaw_base_url",
    );
    expect(baseUrlEnv.name).toBe("ONECLAW_BASE_URL");
    expect(baseUrlEnv.value).toBe("https://api.1claw.xyz");

    const mcpScript = findResourceInstance(
      state,
      "coder_script",
      "oneclaw_mcp_setup",
    );
    expect(mcpScript.display_name).toBe("1Claw MCP Setup");

    const bootstrapScripts = state.resources.filter(
      (r) => r.type === "coder_script" && r.name === "oneclaw_bootstrap",
    );
    expect(bootstrapScripts.length).toBe(0);

    const provisions = state.resources.filter(
      (r) => r.type === "null_resource" && r.name === "oneclaw_provision",
    );
    expect(provisions.length).toBe(0);
  });

  it("bootstrap mode creates bootstrap script", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      human_api_key: "1ck_test_human_key",
    });

    const bootstrap = findResourceInstance(
      state,
      "coder_script",
      "oneclaw_bootstrap",
    );
    expect(bootstrap.display_name).toBe("1Claw Bootstrap");

    const provisions = state.resources.filter(
      (r) => r.type === "null_resource" && r.name === "oneclaw_provision",
    );
    expect(provisions.length).toBe(0);
  });

  it("custom base_url is reflected in env", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      vault_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      api_token: "ocv_testtoken",
      base_url: "https://api.example.com",
    });

    const baseUrlEnv = findResourceInstance(
      state,
      "coder_env",
      "oneclaw_base_url",
    );
    expect(baseUrlEnv.value).toBe("https://api.example.com");
  });
});
