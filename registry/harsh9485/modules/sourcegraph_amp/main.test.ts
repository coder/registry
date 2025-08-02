import { describe, it, expect } from "bun:test";
import {
  runTerraformInit,
  runTerraformApply,
  testRequiredVariables,
  findResourceInstance,
} from "~test";
import path from "path";

const moduleDir = path.resolve(__dirname);
const requiredVars = { agent_id: "dummy-agent-id" };

describe("sourcegraph-amp module", () => {
  it("initializes and applies without errors", async () => {
    await runTerraformInit(moduleDir);
    testRequiredVariables(moduleDir, requiredVars);

    const state = await runTerraformApply(moduleDir, requiredVars);
    const script = findResourceInstance(state, "coder_script");

    expect(script).toBeDefined();
    expect(script.agent_id).toBe(requiredVars.agent_id);
    expect(script.script).toContain("ARG_INSTALL_SOURCEGRAPH_AMP='true'");
    expect(script.script).toContain("ARG_AGENTAPI_VERSION='v0.3.0'");
    expect(script.script).toMatch(/\/tmp\/install\.sh/);
    expect(script.script).toMatch(/\/tmp\/start\.sh/);
  });
});