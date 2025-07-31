import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("fly-region", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {});

  it("default output", async () => {
    const state = await runTerraformApply(import.meta.dir, {});
    expect(state.outputs.value.value).toBe("");
  });

  it("customized default", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      default: "atl",
    });
    expect(state.outputs.value.value).toBe("atl");
  });

  it("region filter", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      default: "atl",
      regions: '["arn", "ams", "bos"]',
    });
    expect(state.outputs.value.value).toBe("");
  });
});
