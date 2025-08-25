import { describe, expect, it } from "bun:test";
import {
  executeScriptInContainer,
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

  // Keep all existing tests...

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

  // Add this new test case for extensions and settings
  it("installs extensions and applies settings", async () => {
    const settings = JSON.stringify(
      {
        "editor.fontSize": 14,
        "terminal.integrated.fontSize": 12,
      },
      null,
      2,
    );

    const extensions = ["ms-python.python", "golang.go"];

    await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      extensions: extensions,
      settings: settings,
    });

    const checkScript = `
      set -e
      # The test environment may not have 'code' in the PATH immediately
      # so we add the known location.
      export PATH="$PATH:/tmp/coder/bin"
      
      # Verify extensions
      INSTALLED_EXTENSIONS=$(code --list-extensions)
      echo "$INSTALLED_EXTENSIONS" | grep -q "ms-python.python"
      echo "$INSTALLED_EXTENSIONS" | grep -q "golang.go"

      # Verify settings
      cat /home/coder/.vscode-server/data/Machine/settings.json
    `;

    const result = await executeScriptInContainer(checkScript);
    expect(result.exitCode).toBe(0);
    // Use JSON.parse to compare objects, ignoring formatting differences.
    expect(JSON.parse(result.stdout)).toEqual(JSON.parse(settings));
  });
});