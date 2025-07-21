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

describe("gemini module", async () => {
  await runTerraformInit(moduleDir);

  // 1. Required variables
  testRequiredVariables(moduleDir, requiredVars);

  // 2. coder_script resource is created
  it("creates coder_script resource", async () => {
    const state = await runTerraformApply(moduleDir, requiredVars);
    const scriptResource = findResourceInstance(state, "coder_script");
    expect(scriptResource).toBeDefined();
    expect(scriptResource.agent_id).toBe(requiredVars.agent_id);

    // check that the script contains expected components based on actual content
    expect(scriptResource.script).toContain("ARG_MODULE_DIR_NAME='.gemini-module'");
    expect(scriptResource.script).toContain("ARG_INSTALL_AGENTAPI='true'");
    expect(scriptResource.script).toContain("ARG_AGENTAPI_VERSION='v0.2.3'");
    expect(scriptResource.script).toContain("/tmp/main.sh");
  });
});