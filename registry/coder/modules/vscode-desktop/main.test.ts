import { describe, expect, it } from "bun:test";
import {
  executeScriptInContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  runContainer,
  execContainer,
  removeContainer,
  findResourceInstance,
  readFileContainer,
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
      (res) =>
        res.type === "coder_app" &&
        res.module === "module.vscode-desktop-core" &&
        res.name === "vscode-desktop",
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

  it("does not create extensions script when no extensions or settings", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });

    const script = state.resources.find(
      (res) =>
        res.type === "coder_script" &&
        res.name === "vscode-desktop-extensions",
    );
    expect(script).toBeUndefined();
  });

  it("creates extensions script when extensions are specified", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      extensions: '["ms-python.python", "esbenp.prettier-vscode"]',
    });

    const script = findResourceInstance(
      state,
      "coder_script",
      "vscode-desktop-extensions",
    );
    expect(script).toBeDefined();
    expect(script.display_name).toBe("VS Code Desktop Extensions");
    expect(script.run_on_start).toBe(true);
    expect(script.start_blocks_login).toBe(false);
    expect(script.script).toContain("ms-python.python");
    expect(script.script).toContain("esbenp.prettier-vscode");
  });

  it("creates extensions script when settings are specified", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      settings: JSON.stringify({
        "editor.fontSize": 14,
        "editor.tabSize": 2,
      }),
    });

    const script = findResourceInstance(
      state,
      "coder_script",
      "vscode-desktop-extensions",
    );
    expect(script).toBeDefined();
    expect(script.script).toContain("SETTINGS_B64");
  });

  it("writes settings to machine settings file", async () => {
    const id = await runContainer("alpine/curl");

    try {
      const settings = {
        "editor.fontSize": 14,
        "editor.tabSize": 2,
      };

      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        settings: JSON.stringify(settings),
      });

      const script = findResourceInstance(
        state,
        "coder_script",
        "vscode-desktop-extensions",
      ).script;

      const resp = await execContainer(id, ["sh", "-c", script]);
      expect(resp.exitCode).toBe(0);

      const content = await readFileContainer(
        id,
        "/root/.vscode-server/data/Machine/settings.json",
      );
      const parsed = JSON.parse(content);
      expect(parsed["editor.fontSize"]).toBe(14);
      expect(parsed["editor.tabSize"]).toBe(2);
    } finally {
      await removeContainer(id);
    }
  }, 15000);

  it("merges settings with existing machine settings", async () => {
    const id = await runContainer("alpine/curl");

    try {
      // Pre-populate existing settings
      await execContainer(id, [
        "sh",
        "-c",
        'mkdir -p /root/.vscode-server/data/Machine && echo \'{"editor.wordWrap":"on","editor.fontSize":12}\' > /root/.vscode-server/data/Machine/settings.json',
      ]);

      // Install jq for merge support
      await execContainer(id, ["apk", "add", "--no-cache", "jq"]);

      const settings = {
        "editor.fontSize": 14,
        "editor.tabSize": 2,
      };

      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        settings: JSON.stringify(settings),
      });

      const script = findResourceInstance(
        state,
        "coder_script",
        "vscode-desktop-extensions",
      ).script;

      const resp = await execContainer(id, ["sh", "-c", script]);
      expect(resp.exitCode).toBe(0);

      const content = await readFileContainer(
        id,
        "/root/.vscode-server/data/Machine/settings.json",
      );
      const parsed = JSON.parse(content);
      // New settings applied
      expect(parsed["editor.fontSize"]).toBe(14);
      expect(parsed["editor.tabSize"]).toBe(2);
      // Existing settings preserved
      expect(parsed["editor.wordWrap"]).toBe("on");
    } finally {
      await removeContainer(id);
    }
  }, 15000);
});
