import { describe, expect, it } from "bun:test";
import { runTerraformApply, runTerraformInit } from "~test";

describe("vscode-web", async () => {
  await runTerraformInit(import.meta.dir);

  it("accept_license should be set to true", () => {
    const t = async () => {
      await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: "false",
      });
    };
    expect(t).toThrow("Invalid value for variable");
  });

  it("use_cached and offline can not be used together", () => {
    const t = async () => {
      await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: "true",
        use_cached: "true",
        offline: "true",
      });
    };
    expect(t).toThrow("Offline and Use Cached can not be used together");
  });

  it("offline and extensions can not be used together", () => {
    const t = async () => {
      await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: "true",
        offline: "true",
        extensions: '["1", "2"]',
      });
    };
    expect(t).toThrow("Offline mode does not allow extensions to be installed");
  });

  it("folder and workspace can not be used together", () => {
    const t = async () => {
      await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: "true",
        folder: "/home/coder",
        workspace: "/home/coder/project.code-workspace",
      });
    };
    expect(t).toThrow("Cannot specify both 'folder' and 'workspace'. Please use only one.");
  });

  // More tests depend on shebang refactors
});