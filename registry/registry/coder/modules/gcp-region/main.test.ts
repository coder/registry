import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("gcp-region", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {});

  it("default output", async () => {
    const state = await runTerraformApply(import.meta.dir, {});
    expect(state.outputs.value.value).toBe("");
  });

  it("customized default", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      regions: '["asia"]',
      default: "asia-east1-a",
    });
    expect(state.outputs.value.value).toBe("asia-east1-a");
  });

  it("gpu only invalid default", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      regions: '["us-west2"]',
      default: "us-west2-a",
      gpu_only: "true",
    });
    expect(state.outputs.value.value).toBe("");
  });

  it("gpu only valid default", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      regions: '["us-west2"]',
      default: "us-west2-b",
      gpu_only: "true",
    });
    expect(state.outputs.value.value).toBe("us-west2-b");
  });

  it("set custom order for coder_parameter", async () => {
    const order = 99;
    const state = await runTerraformApply(import.meta.dir, {
      coder_parameter_order: order.toString(),
    });
    expect(state.resources).toHaveLength(1);
    expect(state.resources[0].instances[0].attributes.order).toBe(order);
  });
});
