import { describe, expect, it, setDefaultTimeout } from "bun:test";
import {
  execContainer,
  findResourceInstance,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  writeFileContainer,
} from "~test";

setDefaultTimeout(30 * 1000);

const decodeBootstrapScript = (installScript: string): string => {
  const match = installScript.match(/IDE_CLI_INSTALL_SCRIPT_B64='([^']+)'/);
  if (!match) {
    throw new Error(
      "The extension installer does not contain a bootstrap script",
    );
  }
  return Buffer.from(match[1], "base64").toString("utf8");
};

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

    const extensionScripts = state.resources.filter(
      (resource) =>
        resource.type === "coder_script" &&
        resource.name === "install_extensions",
    );
    expect(extensionScripts).toHaveLength(0);
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

  it("passes extensions and VS Code Server paths to the core", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      extensions: JSON.stringify([
        "ms-python.python",
        "esbenp.prettier-vscode@12.4.0",
      ]),
    });
    const extensionInstaller = findResourceInstance(
      state,
      "coder_script",
      "install_extensions",
    );
    const bootstrapScript = decodeBootstrapScript(extensionInstaller.script);

    expect(extensionInstaller.start_blocks_login).toBe(true);
    expect(extensionInstaller.timeout).toBe(1800);
    expect(bootstrapScript).toContain(
      "https://update.code.visualstudio.com/api/latest/server-linux-$remote_arch/stable",
    );
    expect(bootstrapScript).toContain(
      "https://update.code.visualstudio.com/commit:$release_commit/server-linux-$remote_arch/stable",
    );
    expect(extensionInstaller.script).toContain(
      Buffer.from(
        "$HOME/.coder-modules/coder/vscode-desktop/server/bin/code-server",
      ).toString("base64"),
    );
    expect(extensionInstaller.script).toContain(
      Buffer.from("$HOME/.vscode-server/extensions").toString("base64"),
    );
    expect(extensionInstaller.script).toContain(
      Buffer.from("esbenp.prettier-vscode@12.4.0").toString("base64"),
    );
    expect(extensionInstaller.script).not.toContain("--force");
  });

  it("does not download VS Code Server again when its CLI is executable", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      extensions: JSON.stringify(["esbenp.prettier-vscode"]),
    });
    const extensionInstaller = findResourceInstance(
      state,
      "coder_script",
      "install_extensions",
    );
    const bootstrapScript = decodeBootstrapScript(extensionInstaller.script);
    const id = await runContainer("node:22-bookworm-slim");
    const cliPath =
      "/root/.coder-modules/coder/vscode-desktop/server/bin/code-server";

    try {
      await execContainer(
        id,
        ["mkdir", "-p", "/root/.coder-modules/coder/vscode-desktop/server/bin"],
        ["--user", "root"],
      );
      await writeFileContainer(id, cliPath, "#!/bin/sh\nexit 0\n", {
        user: "root",
      });
      await execContainer(id, ["chmod", "755", cliPath], ["--user", "root"]);

      const result = await execContainer(id, ["bash", "-c", bootstrapScript]);
      expect(result.exitCode).toBe(0);
    } finally {
      await removeContainer(id);
    }
  });
});
