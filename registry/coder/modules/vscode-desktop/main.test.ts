import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("vscode-desktop", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("default output", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    expect(state.outputs.vscode_url.value).toBe(
      "vscode://coder.coder-remote/open?owner=default&workspace=default&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );

    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "vscode",
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
    expect(state.outputs.vscode_url.value).toBe(
      "vscode://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );
  });

  it("adds folder and open_recent", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      folder: "/foo/bar",
      open_recent: "true",
    });
    expect(state.outputs.vscode_url.value).toBe(
      "vscode://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&openRecent&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );
  });

  it("adds folder but not open_recent", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      folder: "/foo/bar",
      openRecent: "false",
    });
    expect(state.outputs.vscode_url.value).toBe(
      "vscode://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );
  });

  it("adds open_recent", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      open_recent: "true",
    });
    expect(state.outputs.vscode_url.value).toBe(
      "vscode://coder.coder-remote/open?owner=default&workspace=default&openRecent&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );
  });

  it("expect order to be set", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      order: "22",
    });

    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "vscode",
    );

    expect(coder_app).not.toBeNull();
    expect(coder_app?.instances.length).toBe(1);
    expect(coder_app?.instances[0].attributes.order).toBe(22);
  });

  it("accepts extensions list", async () => {
    const extensions = ["ms-python.python", "golang.go"];
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      extensions: JSON.stringify(extensions),
    });

    const coder_script = state.resources.find(
      (res) => res.type === "coder_script" && res.name === "vscode",
    );

    expect(coder_script).not.toBeNull();
    expect(coder_script?.instances[0].attributes.script).toContain(
      JSON.stringify(extensions),
    );
  });

  it("accepts settings object", async () => {
    const settings = {
      "editor.fontSize": 14,
      "files.autoSave": "afterDelay",
    };
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      settings: JSON.stringify(settings),
    });

    const coder_script = state.resources.find(
      (res) => res.type === "coder_script" && res.name === "vscode",
    );

    expect(coder_script).not.toBeNull();
    expect(coder_script?.instances[0].attributes.script).toContain(
      JSON.stringify(settings),
    );
  });

  it("validates extension format", async () => {
    // This should work (valid format)
    const validState = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      extensions: JSON.stringify(["ms-python.python", "golang.go"]),
    });
    expect(validState).toBeDefined();

    // This should fail (invalid format)
    try {
      await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        extensions: JSON.stringify(["invalid-extension-format"]),
      });
      throw new Error("Should have failed validation");
    } catch (error) {
      expect(error).toBeInstanceOf(Error);
      expect((error as Error).message).toContain(
        "extensions variable must be in the format",
      );
    }
  });
});
