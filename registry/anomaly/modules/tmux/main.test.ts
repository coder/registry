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

describe("tmux module", async () => {
  await runTerraformInit(moduleDir);

  // 1. Required variables
  testRequiredVariables(moduleDir, requiredVars);

  // 2. coder_script resource is created
  it("creates coder_script resource", async () => {
    const state = await runTerraformApply(moduleDir, requiredVars);
    const scriptResource = findResourceInstance(state, "coder_script");
    expect(scriptResource).toBeDefined();
    expect(scriptResource.agent_id).toBe(requiredVars.agent_id);

    // check that the script contains expected lines
    expect(scriptResource.script).toContain("Installing tmux");
    expect(scriptResource.script).toContain(
      "Installing Tmux Plugin Manager (TPM)",
    );
    expect(scriptResource.script).toContain("tmux configuration created at");
    expect(scriptResource.script).toContain("✅ tmux setup complete!");
  });
});
