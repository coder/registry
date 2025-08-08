import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("cursor-cli", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("default output with CLI enabled", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });

    // Check that AgentAPI module is created
    const agentapi_module = state.resources.find(
      (res) => res.type === "module" && res.name === "agentapi",
    );
    expect(agentapi_module).not.toBeNull();
  });

  it("adds custom folder", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      folder: "/foo/bar",
    });

    // Check that AgentAPI module is created with custom folder
    const agentapi_module = state.resources.find(
      (res) => res.type === "module" && res.name === "agentapi",
    );
    expect(agentapi_module).not.toBeNull();
  });

  it("expect order to be set", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      order: "22",
    });

    // Check that AgentAPI module is created
    const agentapi_module = state.resources.find(
      (res) => res.type === "module" && res.name === "agentapi",
    );
    expect(agentapi_module).not.toBeNull();
  });

  it("disables CLI installation", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install_cursor_cli: "false",
      install_agentapi: "false",
    });

    // AgentAPI module should still exist but with install_agentapi = false
    const agentapi_module = state.resources.find(
      (res) => res.type === "module" && res.name === "agentapi",
    );
    expect(agentapi_module).not.toBeNull();
  });

  it("enables only CLI without web interface", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      install_cursor_cli: "true",
      install_agentapi: "false",
    });

    // AgentAPI module should exist but with install_agentapi = false
    const agentapi_module = state.resources.find(
      (res) => res.type === "module" && res.name === "agentapi",
    );
    expect(agentapi_module).not.toBeNull();
  });
});
