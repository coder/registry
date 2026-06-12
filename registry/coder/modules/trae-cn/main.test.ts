import { describe, expect, it } from "bun:test";
import {
  findResourceInstance,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

const encodeBase64 = (value: string) => Buffer.from(value).toString("base64");

describe("trae-cn", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("default output", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    expect(state.outputs.trae_cn_url.value).toBe(
      "trae-cn://coder.coder-remote/open?owner=default&workspace=default&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );

    const coderApp = state.resources.find(
      (res) =>
        res.type === "coder_app" &&
        res.module === "module.vscode-desktop-core" &&
        res.name === "vscode-desktop",
    );

    expect(coderApp).not.toBeNull();
    expect(coderApp?.instances.length).toBe(1);
    expect(coderApp?.instances[0].attributes.icon).toBe("/icon/trae-cn.png");
    expect(coderApp?.instances[0].attributes.slug).toBe("trae-cn");
    expect(coderApp?.instances[0].attributes.display_name).toBe("Trae CN");
    expect(coderApp?.instances[0].attributes.order).toBeNull();
  });

  it("adds folder", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      folder: "/foo/bar",
    });
    expect(state.outputs.trae_cn_url.value).toBe(
      "trae-cn://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );
  });

  it("adds folder and open_recent", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      folder: "/foo/bar",
      open_recent: "true",
    });
    expect(state.outputs.trae_cn_url.value).toBe(
      "trae-cn://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&openRecent&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );
  });

  it("adds folder but not open_recent", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      folder: "/foo/bar",
      open_recent: "false",
    });
    expect(state.outputs.trae_cn_url.value).toBe(
      "trae-cn://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );
  });

  it("adds open_recent", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      open_recent: "true",
    });
    expect(state.outputs.trae_cn_url.value).toBe(
      "trae-cn://coder.coder-remote/open?owner=default&workspace=default&openRecent&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );
  });

  it("sets order", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      order: "22",
    });

    const coderApp = state.resources.find(
      (res) =>
        res.type === "coder_app" &&
        res.module === "module.vscode-desktop-core" &&
        res.name === "vscode-desktop",
    );

    expect(coderApp).not.toBeNull();
    expect(coderApp?.instances.length).toBe(1);
    expect(coderApp?.instances[0].attributes.order).toBe(22);
  });

  it("adds MCP script for folder/.trae/mcp.json when mcp and folder provided", async () => {
    const mcp = JSON.stringify({
      mcpServers: { demo: { url: "http://localhost:1234" } },
    });
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      folder: "/tmp/project",
      mcp,
    });
    const script = findResourceInstance(state, "coder_script", "trae_cn_mcp");

    expect(script.display_name).toBe("Trae CN MCP");
    expect(script.icon).toBe("/icon/trae-cn.png");
    expect(script.script).toContain(encodeBase64(mcp));
    expect(script.script).toContain(
      encodeBase64("/tmp/project/.trae/mcp.json"),
    );
  });

  it("adds MCP script for custom mcp_config_path when provided", async () => {
    const mcp = JSON.stringify({
      mcpServers: { demo: { url: "http://localhost:1234" } },
    });
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      folder: "/tmp/project",
      mcp,
      mcp_config_path: "$HOME/.config/trae/mcp.json",
    });
    const script = findResourceInstance(state, "coder_script", "trae_cn_mcp");

    expect(script.script).toContain(encodeBase64(mcp));
    expect(script.script).toContain(
      encodeBase64("$HOME/.config/trae/mcp.json"),
    );
  });
});
