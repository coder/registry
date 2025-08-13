import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

// hardcoded coder_app name in main.tf
const appName = "vscode-desktop";

const defaultVariables = {
  agent_id: "foo",
  coder_app_icon: "/icon/code.svg",
  coder_app_slug: "vscode",
  coder_app_display_name: "VS Code Desktop",
  protocol: "vscode",
}

describe("vscode-desktop-core", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, defaultVariables);

  it("default output", async () => {
    const state = await runTerraformApply(import.meta.dir, defaultVariables);
    expect(state.outputs.ide_uri.value).toBe(
      `${defaultVariables.protocol}://coder.coder-remote/open?owner=default&workspace=default&url=https://mydeployment.coder.com&token=$SESSION_TOKEN`,
    );

    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === appName,
    );

    expect(coder_app).not.toBeNull();
    expect(coder_app?.instances.length).toBe(1);
    expect(coder_app?.instances[0].attributes.order).toBeNull();
  });

  it("adds folder", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      folder: "/foo/bar",

      ...defaultVariables
    });

    expect(state.outputs.ide_uri.value).toBe(
      `${defaultVariables.protocol}://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&url=https://mydeployment.coder.com&token=$SESSION_TOKEN`,
    );
  });

  it("adds folder and open_recent", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      folder: "/foo/bar",
      open_recent: "true",

      ...defaultVariables,
    });
    expect(state.outputs.ide_uri.value).toBe(
      `${defaultVariables.protocol}://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&openRecent&url=https://mydeployment.coder.com&token=$SESSION_TOKEN`,
    );
  });

  it("adds folder but not open_recent", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      folder: "/foo/bar",
      openRecent: "false",

      ...defaultVariables,
    });
    expect(state.outputs.ide_uri.value).toBe(
      `${defaultVariables.protocol}://coder.coder-remote/open?owner=default&workspace=default&folder=/foo/bar&url=https://mydeployment.coder.com&token=$SESSION_TOKEN`,
    );
  });

  it("adds open_recent", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      open_recent: "true",

      ...defaultVariables,
    });
    expect(state.outputs.ide_uri.value).toBe(
      `${defaultVariables.protocol}://coder.coder-remote/open?owner=default&workspace=default&openRecent&url=https://mydeployment.coder.com&token=$SESSION_TOKEN`,
    );
  });

  it("expect order to be set", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      coder_app_order: "22",
      ...defaultVariables
    });

    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === appName,
    );

    expect(coder_app).not.toBeNull();
    expect(coder_app?.instances.length).toBe(1);
    expect(coder_app?.instances[0].attributes.order).toBe(22);
  });
});
