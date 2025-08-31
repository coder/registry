import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("digitalocean-region", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {});

  it("default output", async () => {
    const state = await runTerraformApply(import.meta.dir, {});
    expect(state.outputs.value.value).toBe("ams2");
  });

  it("customized default", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      regions: '["nyc1","ams3"]',
      default: "ams3",
    });
    expect(state.outputs.value.value).toBe("ams3");
  });

  it("gpu only invalid default", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      regions: '["nyc1"]',
      default: "nyc1",
      gpu_only: "true",
    });
    expect(state.outputs.value.value).toBe("nyc1");
  });

  it("gpu only valid default", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      regions: '["tor1"]',
      default: "tor1",
      gpu_only: "true",
    });
    expect(state.outputs.value.value).toBe("tor1");
  });

  // Add more tests as needed for coder_parameter_order or other features
});
