import { describe, expect, it } from "bun:test";
import {
  executeScriptInContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("vscode-desktop-enhanced", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("default output without extensions", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    
    expect(state.outputs.vscode_url.value).toBe(
      "vscode://coder.coder-remote/open?owner=default&workspace=default&url=https://mydeployment.coder.com&token=$SESSION_TOKEN",
    );
    
    expect(state.outputs.extensions_installed.value).toEqual([]);
    expect(state.outputs.settings_applied.value).toBe("No custom settings");

    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "vscode",
    );

    expect(coder_app).not.toBeNull();
    expect(coder_app?.instances.length).toBe(1);
    expect(coder_app?.instances[0].attributes.order).toBeNull();
    
    // Should not create script resource when no extensions or settings
    const coder_script = state.resources.find(
      (res) => res.type === "coder_script" && res.name === "vscode_setup",
    );
    expect(coder_script).toBeUndefined();
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

  it("configures extensions", async () => {
    const extensions = ["ms-python.python", "ms-vscode.vscode-typescript-next"];
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      extensions: JSON.stringify(extensions),
    });
    
    expect(state.outputs.extensions_installed.value).toEqual(extensions);
    expect(state.outputs.settings_applied.value).toBe("No custom settings");
    
    // Should create script resource when extensions are provided
    const coder_script = state.resources.find(
      (res) => res.type === "coder_script" && res.name === "vscode_setup",
    );
    expect(coder_script).not.toBeNull();
    expect(coder_script?.instances.length).toBe(1);
    expect(coder_script?.instances[0].attributes.display_name).toBe("VS Code Setup");
    expect(coder_script?.instances[0].attributes.run_on_start).toBe(true);
  });

  it("configures custom settings", async () => {
    const settings = JSON.stringify({
      "editor.fontSize": 14,
      "workbench.colorTheme": "Dark+ (default dark)"
    });
    
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      settings: settings,
    });
    
    expect(state.outputs.extensions_installed.value).toEqual([]);
    expect(state.outputs.settings_applied.value).toBe("Custom settings applied");
    
    // Should create script resource when settings are provided
    const coder_script = state.resources.find(
      (res) => res.type === "coder_script" && res.name === "vscode_setup",
    );
    expect(coder_script).not.toBeNull();
  });

  it("configures both extensions and settings", async () => {
    const extensions = ["ms-python.python", "esbenp.prettier-vscode"];
    const settings = JSON.stringify({
      "python.defaultInterpreterPath": "/usr/bin/python3",
      "editor.formatOnSave": true
    });
    
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      extensions: JSON.stringify(extensions),
      settings: settings,
      folder: "/workspace",
      order: 1,
      group: "Development",
    });
    
    expect(state.outputs.extensions_installed.value).toEqual(extensions);
    expect(state.outputs.settings_applied.value).toBe("Custom settings applied");
    
    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "vscode",
    );
    expect(coder_app?.instances[0].attributes.order).toBe(1);
    expect(coder_app?.instances[0].attributes.group).toBe("Development");
    
    const coder_script = state.resources.find(
      (res) => res.type === "coder_script" && res.name === "vscode_setup",
    );
    expect(coder_script).not.toBeNull();
    expect(coder_script?.instances[0].attributes.agent_id).toBe("foo");
  });

  it("handles empty extensions list", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      extensions: "[]",
    });
    
    expect(state.outputs.extensions_installed.value).toEqual([]);
    
    // Should not create script resource for empty extensions list
    const coder_script = state.resources.find(
      (res) => res.type === "coder_script" && res.name === "vscode_setup",
    );
    expect(coder_script).toBeUndefined();
  });

  it("handles complex settings object", async () => {
    const complexSettings = JSON.stringify({
      "editor.formatOnSave": true,
      "editor.codeActionsOnSave": {
        "source.fixAll.eslint": true
      },
      "prettier.singleQuote": true,
      "workbench.startupEditor": "newUntitledFile",
      "terminal.integrated.defaultProfile.linux": "bash",
      "files.associations": {
        "*.json": "jsonc"
      }
    });
    
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      settings: complexSettings,
    });
    
    expect(state.outputs.settings_applied.value).toBe("Custom settings applied");
    
    const coder_script = state.resources.find(
      (res) => res.type === "coder_script" && res.name === "vscode_setup",
    );
    expect(coder_script).not.toBeNull();
  });
});
