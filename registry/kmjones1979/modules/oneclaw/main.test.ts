import { describe, expect, it } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  findResourceInstance,
} from "~test";

const installScriptTemplate = readFileSync(
  join(import.meta.dir, "scripts/install.sh.tftpl"),
  "utf8",
);

describe("oneclaw", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "test-agent",
  });

  it("manual mode sets env vars and uses coder-utils", async () => {
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

    const installScripts = state.resources.filter(
      (r) =>
        r.type === "coder_script" &&
        r.instances[0].attributes.display_name === "1Claw: Install Script",
    );
    expect(installScripts.length).toBe(1);

    expect(state.outputs.scripts.value).toEqual([
      "kmjones1979-oneclaw-install_script",
    ]);
    expect(state.outputs.module_directory.value).toBe(
      "$HOME/.coder-modules/kmjones1979/oneclaw",
    );

    const provisions = state.resources.filter(
      (r) => r.type === "null_resource" && r.name === "provision",
    );
    expect(provisions.length).toBe(0);
  });

  it("bootstrap mode injects human key via coder_env, not the install template", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      human_api_key: "1ck_test_human_key",
    });

    const humanKeyEnv = findResourceInstance(
      state,
      "coder_env",
      "human_api_key",
    );
    expect(humanKeyEnv.name).toBe("_ONECLAW_HUMAN_API_KEY");

    expect(installScriptTemplate).toContain("_ONECLAW_HUMAN_API_KEY");
    expect(installScriptTemplate).not.toContain("1ck_test_human_key");

    expect(state.outputs.provisioning_mode.value).toBe("bootstrap");
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
