import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("kiro", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("default output", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    expect(state.outputs.kiro_url.value).toBe(
      "kiro://coder.coder-remote/open?owner=default&workspace=default&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );

    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "kiro",
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
    expect(state.outputs.kiro_url.value).toBe(
      "kiro://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );
  });

  it("adds folder and open_recent", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      folder: "/foo/bar",
      open_recent: "true",
    });
    expect(state.outputs.kiro_url.value).toBe(
      "kiro://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&openRecent&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );
  });

  it("custom slug and display_name", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      slug: "kiro-ai",
      display_name: "Kiro AI IDE",
    });
    
    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "kiro",
    );

    expect(coder_app?.instances[0].attributes.slug).toBe("kiro-ai");
    expect(coder_app?.instances[0].attributes.display_name).toBe("Kiro AI IDE");
  });

  it("sets order", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      order: "5",
    });
    
    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "kiro",
    );

    expect(coder_app?.instances[0].attributes.order).toBe(5);
  });

  it("sets group", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      group: "AI IDEs",
    });
    
    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "kiro",
    );

    expect(coder_app?.instances[0].attributes.group).toBe("AI IDEs");
  });
});
