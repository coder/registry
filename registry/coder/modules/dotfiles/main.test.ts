import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("dotfiles", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("default output", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    expect(state.outputs.dotfiles_uri.value).toBe("");
  });

  it("set a default dotfiles_uri", async () => {
    const default_dotfiles_uri = "foo";
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      default_dotfiles_uri,
    });
    expect(state.outputs.dotfiles_uri.value).toBe(default_dotfiles_uri);
  });

  it("set custom order for coder_parameter", async () => {
    const order = 99;
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      coder_parameter_order: order.toString(),
    });
    expect(state.resources).toHaveLength(2);
    expect(state.resources[0].instances[0].attributes.order).toBe(order);
  });

  it("set custom dotfiles_branch", async () => {
    const branch = "develop";
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      dotfiles_branch: branch,
    });
    expect(state.resources).toHaveLength(2);
    // Check that the script contains the custom branch
    const scriptResource = state.resources.find(r => r.type === "coder_script");
    expect(scriptResource?.instances[0].attributes.script).toContain(`DOTFILES_BRANCH="${branch}"`);
  });

  it("default dotfiles_branch creates parameter", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    // Should have coder_script, coder_parameter for dotfiles_uri, and coder_parameter for dotfiles_branch
    expect(state.resources).toHaveLength(3);
    const branchParameter = state.resources.find(r => r.type === "coder_parameter" && r.instances[0].attributes.name === "dotfiles_branch");
    expect(branchParameter).toBeDefined();
    expect(branchParameter?.instances[0].attributes.default).toBe("main");
  });
});
