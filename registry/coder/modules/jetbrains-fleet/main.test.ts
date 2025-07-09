import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("jetbrains-fleet", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("default output", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    expect(state.outputs.fleet_url.value).toBe(
      "fleet://fleet.ssh/default.coder",
    );

    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "fleet",
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
    expect(state.outputs.fleet_url.value).toBe(
      "fleet://fleet.ssh/default.coder?pwd=/foo/bar",
    );
  });

  it("adds agent_name to hostname", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      agent_name: "myagent",
    });
    expect(state.outputs.fleet_url.value).toBe(
      "fleet://fleet.ssh/myagent.default.default.coder",
    );
  });

  it("custom display name and slug", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      display_name: "My Fleet",
      slug: "my-fleet",
    });
    expect(state.outputs.fleet_url.value).toBe(
      "fleet://fleet.ssh/default.coder",
    );

    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "fleet",
    );

    expect(coder_app).not.toBeNull();
    expect(coder_app?.instances[0].attributes.display_name).toBe("My Fleet");
    expect(coder_app?.instances[0].attributes.slug).toBe("my-fleet");
  });

  it("expect order to be set", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      order: "22",
    });

    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "fleet",
    );

    expect(coder_app).not.toBeNull();
    expect(coder_app?.instances.length).toBe(1);
    expect(coder_app?.instances[0].attributes.order).toBe(22);
  });

  it("expect group to be set", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      group: "JetBrains IDEs",
    });

    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "fleet",
    );

    expect(coder_app).not.toBeNull();
    expect(coder_app?.instances.length).toBe(1);
    expect(coder_app?.instances[0].attributes.group).toBe("JetBrains IDEs");
  });
}); 