import { describe, expect, it } from "bun:test";
import {
  findResourceInstance,
  runTerraformInit,
  runTerraformApply,
  testRequiredVariables,
} from "~test";

describe("digitalocean-region", async () => {
  type TestVariables = {
    default?: string;
    mutable?: boolean;
    name?: string;
    display_name?: string;
    description?: string;
    icon?: string;
  };

  await runTerraformInit(import.meta.dir);

  it("can run apply with no variables", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {});
    const parameter = findResourceInstance(state, "coder_parameter");
    expect(parameter.name).toBe("region");
    expect(parameter.display_name).toBe("Region");
    expect(parameter.default).toBe("ams3");
    expect(parameter.mutable).toBe(false);
    expect(parameter.type).toBe("string");
    expect(parameter.icon).toBe("/emojis/1f30e.png");
  });

  it("can customize default region", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      default: "sfo3",
    });
    const parameter = findResourceInstance(state, "coder_parameter");
    expect(parameter.default).toBe("sfo3");
  });

  it("can make region mutable", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      mutable: true,
    });
    const parameter = findResourceInstance(state, "coder_parameter");
    expect(parameter.mutable).toBe(true);
  });

  it("can customize parameter details", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      name: "datacenter",
      display_name: "Datacenter Location",
      description: "Select your preferred datacenter",
      icon: "/emojis/1f4cd.png",
    });
    const parameter = findResourceInstance(state, "coder_parameter", "region");
    expect(parameter.name).toBe("datacenter");
    expect(parameter.display_name).toBe("Datacenter Location");
    expect(parameter.description).toBe("Select your preferred datacenter");
    expect(parameter.icon).toBe("/emojis/1f4cd.png");
  });

  it("includes all expected region options", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {});
    const parameter = findResourceInstance(state, "coder_parameter");
    
    const expectedRegions = [
      { value: "tor1", name: "Canada (Toronto)", icon: "/emojis/1f1e8-1f1e6.png", description: "" },
      { value: "fra1", name: "Germany (Frankfurt)", icon: "/emojis/1f1e9-1f1ea.png", description: "" },
      { value: "blr1", name: "India (Bangalore)", icon: "/emojis/1f1ee-1f1f3.png", description: "" },
      { value: "ams3", name: "Netherlands (Amsterdam)", icon: "/emojis/1f1f3-1f1f1.png", description: "" },
      { value: "sgp1", name: "Singapore", icon: "/emojis/1f1f8-1f1ec.png", description: "" },
      { value: "lon1", name: "United Kingdom (London)", icon: "/emojis/1f1ec-1f1e7.png", description: "" },
      { value: "sfo2", name: "United States (California - 2)", icon: "/emojis/1f1fa-1f1f8.png", description: "" },
      { value: "sfo3", name: "United States (California - 3)", icon: "/emojis/1f1fa-1f1f8.png", description: "" },
      { value: "nyc1", name: "United States (New York - 1)", icon: "/emojis/1f1fa-1f1f8.png", description: "" },
      { value: "nyc3", name: "United States (New York - 3)", icon: "/emojis/1f1fa-1f1f8.png", description: "" },
    ];

    expect(parameter.option).toHaveLength(expectedRegions.length);
    
    expectedRegions.forEach((expectedRegion, index) => {
      expect(parameter.option[index]).toEqual(expectedRegion);
    });
  });

  it("outputs the correct values", async () => {
    const state = await runTerraformApply<TestVariables>(import.meta.dir, {
      default: "sfo3",
      name: "test_region",
      display_name: "Test Region",
    });
    
    expect(state.outputs.value.value).toBe("sfo3");
    expect(state.outputs.name.value).toBe("test_region");
    expect(state.outputs.display_name.value).toBe("Test Region");
  });
});