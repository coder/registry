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

  it("manual mode sets env vars and run script", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      vault_id: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
      api_token: "ocv_testtoken",
    });

    const vaultEnv = findResourceInstance(state, "coder_env", "vault_id");
    expect(vaultEnv.name).toBe("ONECLAW_VAULT_ID");

    const apiKeyEnv = findResourceInstance(state, "coder_env", "agent_api_key");
    expect(apiKeyEnv.name).toBe("ONECLAW_AGENT_API_KEY");

    const baseUrlEnv = findResourceInstance(state, "coder_env", "base_url");
    expect(baseUrlEnv.name).toBe("ONECLAW_BASE_URL");
    expect(baseUrlEnv.value).toBe("https://api.1claw.xyz");

    const runScript = findResourceInstance(state, "coder_script", "run");
    expect(runScript.display_name).toBe("1Claw");
    expect(runScript.start_blocks_login).toBe(false);

    const provisions = state.resources.filter(
      (r) => r.type === "null_resource" && r.name === "provision",
    );
    expect(provisions.length).toBe(0);
  });

  it("bootstrap mode enables blocking run script and injects human key via coder_env", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      human_api_key: "1ck_test_human_key",
    });

    const runScript = findResourceInstance(state, "coder_script", "run");
    expect(runScript.display_name).toBe("1Claw");
    expect(runScript.start_blocks_login).toBe(true);

    // The human key is delivered via coder_env (sensitive), NOT baked into the
    // script body, so it never lands in the Coder agent's script log.
    const humanKeyEnv = findResourceInstance(
      state,
      "coder_env",
      "human_api_key",
    );
    expect(humanKeyEnv.name).toBe("_ONECLAW_HUMAN_API_KEY");

    // And the actual key value must not appear anywhere in the rendered script text.
    expect(runScript.script).not.toContain("1ck_test_human_key");
    // The script must reference the env var, not a literal value.
    expect(runScript.script).toContain("_ONECLAW_HUMAN_API_KEY");

    const provisions = state.resources.filter(
      (r) => r.type === "null_resource" && r.name === "provision",
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

    const baseUrlEnv = findResourceInstance(state, "coder_env", "base_url");
    expect(baseUrlEnv.value).toBe("https://api.example.com");
  });
});
