import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("cursor", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("default output with CLI enabled", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    
    // Check desktop app output
    expect(state.outputs.cursor_desktop_url.value).toBe(
      "cursor://coder.coder-remote/open?owner=default&workspace=default&folder=/home/coder&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );

    // Check that AgentAPI module is created
    const agentapi_module = state.resources.find(
      (res) => res.type === "module" && res.name === "agentapi",
    );
    expect(agentapi_module).not.toBeNull();

    // Check desktop app resource
    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "cursor_desktop",
    );
    expect(coder_app).not.toBeNull();
    expect(coder_app?.instances.length).toBe(1);
    expect(coder_app?.instances[0].attributes.order).toBeNull();
  });

  it("adds custom folder", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      folder: "/foo/bar",
    });
    expect(state.outputs.cursor_desktop_url.value).toBe(
      "cursor://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );
  });

  it("adds folder and open_recent", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      folder: "/foo/bar",
      open_recent: "true",
    });
    expect(state.outputs.cursor_desktop_url.value).toBe(
      "cursor://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&openRecent&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );
  });

  it("adds open_recent with default folder", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      open_recent: "true",
    });
    expect(state.outputs.cursor_desktop_url.value).toBe(
      "cursor://coder.coder-remote/open?owner=default&workspace=default&folder=/home/coder&openRecent&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );
  });

  it("expect order to be set", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      order: "22",
    });

    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "cursor_desktop",
    );

    expect(coder_app).not.toBeNull();
    expect(coder_app?.instances.length).toBe(1);
    expect(coder_app?.instances[0].attributes.order).toBe(23); // order + 1 for desktop app
  });

  it("disables CLI installation", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install_cursor_cli: "false",
      install_agentapi: "false",
    });

    // Should still have desktop app
    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "cursor_desktop",
    );
    expect(coder_app).not.toBeNull();

    // AgentAPI module should still exist but with install_agentapi = false
    const agentapi_module = state.resources.find(
      (res) => res.type === "module" && res.name === "agentapi",
    );
    expect(agentapi_module).not.toBeNull();
  });
});
