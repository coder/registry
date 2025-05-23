import { it, expect, describe } from "bun:test";
import {
  runTerraformInit,
  testRequiredVariables,
  runTerraformApply,
} from "~test";

describe("jetbrains", async () => {
  await runTerraformInit(import.meta.dir);

  await testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
    folder: "/home/foo",
  });

  it("should create a link with the default values", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      // These are all required.
      agent_id: "foo",
      folder: "/home/coder",
    });
    
    // Check that the URL contains the expected components
    const url = state.outputs.url.value;
    expect(url).toContain("jetbrains://gateway/com.coder.toolbox");
    expect(url).toMatch(/workspace=[^&]+/);
    expect(url).toContain("owner=default");
    expect(url).toContain("project_path=/home/coder");
    expect(url).toContain("token=$SESSION_TOKEN");
    expect(url).toContain("ide_product_code=CL"); // First option in the default list

    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "jetbrains",
    );

    expect(coder_app).not.toBeNull();
    expect(coder_app?.instances.length).toBe(1);
    expect(coder_app?.instances[0].attributes.order).toBeNull();
  });

  it("should use the specified default IDE", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      folder: "/home/foo",
      default: "GO",
    });
    expect(state.outputs.identifier.value).toBe("GO");
  });

  it("should use the first IDE from options when no default is specified", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      folder: "/home/foo",
      options: '["PY", "GO", "IU"]',
    });
    expect(state.outputs.identifier.value).toBe("PY");
  });

  it("should set the app order when specified", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      folder: "/home/foo",
      coder_app_order: 42,
    });
    
    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "jetbrains",
    );

    expect(coder_app).not.toBeNull();
    expect(coder_app?.instances[0].attributes.order).toBe(42);
  });

  it("should use the latest build number when latest is true", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      folder: "/home/foo",
      latest: true,
    });
    
    // We can't test the exact build number since it's fetched dynamically,
    // but we can check that the URL contains the build number parameter
    const url = state.outputs.url.value;
    expect(url).toContain("ide_build_number=");
  });
});
