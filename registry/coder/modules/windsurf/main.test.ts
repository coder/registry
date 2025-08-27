import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  runContainer,
  execContainer,
  removeContainer,
  findResourceInstance,
  readFileContainer,
} from "~test";

describe("windsurf", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("default output", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    expect(state.outputs.windsurf_url.value).toBe(
      "windsurf://coder.coder-remote/open?owner=default&workspace=default&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );

    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "windsurf",
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
    expect(state.outputs.windsurf_url.value).toBe(
      "windsurf://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );
  });

  it("adds folder and open_recent", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      folder: "/foo/bar",
      open_recent: true,
    });
    expect(state.outputs.windsurf_url.value).toBe(
      "windsurf://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&openRecent&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );
  });

  it("adds folder but not open_recent", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      folder: "/foo/bar",
      open_recent: false,
    });
    expect(state.outputs.windsurf_url.value).toBe(
      "windsurf://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );
  });

  it("adds open_recent", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      open_recent: true,
    });
    expect(state.outputs.windsurf_url.value).toBe(
      "windsurf://coder.coder-remote/open?owner=default&workspace=default&openRecent&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );
  });

  it("expect order to be set", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      order: 22,
    });

    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "windsurf",
    );

    expect(coder_app).not.toBeNull();
    expect(coder_app?.instances.length).toBe(1);
    expect(coder_app?.instances[0].attributes.order).toBe(22);
  });

  it("writes ~/.codeium/windsurf/mcp_config.json when mcp provided", async () => {
    const id = await runContainer("alpine");
    try {
      const mcp = JSON.stringify({ servers: { demo: { url: "http://localhost:1234" } } });
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        mcp,
      });
      const script = findResourceInstance(state, "coder_script", "windsurf_mcp").script;
      const resp = await execContainer(id, ["sh", "-c", script]);
      if (resp.exitCode !== 0) {
        console.log(resp.stdout);
        console.log(resp.stderr);
      }
      expect(resp.exitCode).toBe(0);
      const content = await readFileContainer(id, "/root/.codeium/windsurf/mcp_config.json");
      expect(content).toBe(mcp);
    } finally {
      await removeContainer(id);
    }
  });
});
