import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("zed", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("default output", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    expect(state.outputs.zed_url.value).toBe(
      "zed://ssh/default.coder",
    );

    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "zed",
    );

    expect(coder_app).not.toBeNull();
    expect(coder_app?.instances.length).toBe(1);
    expect(coder_app?.instances[0].attributes.order).toBeNull();
  });

  it("adds folder", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      folder: "/foo/bar",
    });
    expect(state.outputs.zed_url.value).toBe(
      "zed://ssh/default.coder/foo/bar",
    );
  });

  it("expect order to be set", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      order: "22",
    });

    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "zed",
    );

    expect(coder_app).not.toBeNull();
    expect(coder_app?.instances.length).toBe(1);
    expect(coder_app?.instances[0].attributes.order).toBe(22);
  });

  it("expect display_name to be set", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      display_name: "Custom Zed",
    });

    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "zed",
    );

    expect(coder_app).not.toBeNull();
    expect(coder_app?.instances.length).toBe(1);
    expect(coder_app?.instances[0].attributes.display_name).toBe("Custom Zed");
  });

  it("adds agent_name to hostname", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      agent_name: "myagent",
    });
    expect(state.outputs.zed_url.value).toBe(
      "zed://ssh/myagent.default.default.coder",
    );
  });
});
