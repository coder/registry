import { describe, it, expect } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  findResourceInstance,
} from "~test";
import path from "path";

const moduleDir = path.resolve(__dirname);

const requiredVars = {
  agent_id: "dummy-agent-id",
};

describe("amazon-q module", async () => {
  await runTerraformInit(moduleDir);

  // 1. Required variables
  testRequiredVariables(moduleDir, requiredVars);

  // 2. coder_script resource is created
  it("creates coder_script resource", async () => {
    const state = await runTerraformApply(moduleDir, requiredVars);
    const scriptResource = findResourceInstance(state, "coder_script");
    expect(scriptResource).toBeDefined();
    expect(scriptResource.agent_id).toBe(requiredVars.agent_id);
    // The script is base64 encoded, so let's check for the module
    expect(scriptResource.script).toContain("ARG_INSTALL_SCRIPT");
  });

  // 3. coder_app resource is created (from AgentAPI module)
  it("creates coder_app resource", async () => {
    const state = await runTerraformApply(moduleDir, requiredVars);
    // The AgentAPI module creates apps with names "agentapi_web" and "agentapi_cli"
    const webAppResource = findResourceInstance(state, "coder_app", "agentapi_web");
    expect(webAppResource).toBeDefined();
    expect(webAppResource.agent_id).toBe(requiredVars.agent_id);
    
    const cliAppResource = findResourceInstance(state, "coder_app", "agentapi_cli");
    expect(cliAppResource).toBeDefined();
    expect(cliAppResource.agent_id).toBe(requiredVars.agent_id);
  });

  // Add more state-based tests as needed
});
