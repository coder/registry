import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("parsec", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("accepts valid installation methods", async () => {
    await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      installation_method: "auto",
    });

    await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      installation_method: "deb",
    });

    await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      installation_method: "appimage",
    });
  });

  it("rejects invalid installation methods", () => {
    const t = async () => {
      await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        installation_method: "invalid",
      });
    };
    expect(t).toThrow("Installation method must be one of: auto, deb, appimage");
  });

  it("accepts hardware acceleration settings", async () => {
    await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      enable_hardware_acceleration: true,
    });

    await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      enable_hardware_acceleration: false,
    });
  });

    it("sets default values correctly", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });

    // Check that default values are applied
    expect(state.outputs.parsec_info.value.installation_method).toBe("auto");
    expect(state.outputs.parsec_info.value.hardware_acceleration).toBe(true);
  });

  it("configures UI positioning", async () => {
    await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      order: 1,
      group: "Remote Access",
    });
  });
}); 