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
});
