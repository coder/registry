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

// hardcoded coder_app name in main.tf
const appName = "vscode-desktop";

const defaultVariables = {
  agent_id: "foo",

  coder_app_icon: "/icon/code.svg",
  coder_app_slug: "vscode",
  coder_app_display_name: "VS Code Desktop",

  protocol: "vscode",
  config_folder: "$HOME/.vscode",
};

describe("vscode-desktop-core", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, defaultVariables);

  describe("coder_app", () => {
    describe("IDE URI attributes", () => {
      it("default output", async () => {
        const state = await runTerraformApply(
          import.meta.dir,
          defaultVariables,
        );
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

          ...defaultVariables,
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
    });

    it("sets custom slug and display_name", async () => {
      const state = await runTerraformApply(import.meta.dir, defaultVariables);

      const coder_app = state.resources.find(
        (res) => res.type === "coder_app" && res.name === appName,
      );

      expect(coder_app?.instances[0].attributes.slug).toBe(
        defaultVariables.coder_app_slug,
      );
      expect(coder_app?.instances[0].attributes.display_name).toBe(
        defaultVariables.coder_app_display_name,
      );
    });

    it("sets order", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        coder_app_order: "5",

        ...defaultVariables,
      });

      const coder_app = state.resources.find(
        (res) => res.type === "coder_app" && res.name === appName,
      );

      expect(coder_app?.instances[0].attributes.order).toBe(5);
    });

    it("sets group", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        coder_app_group: "web-app-group",

        ...defaultVariables,
      });

      const coder_app = state.resources.find(
        (res) => res.type === "coder_app" && res.name === appName,
      );

      expect(coder_app?.instances[0].attributes.group).toBe("web-app-group");
    });
  });

  it("writes mcp_config.json when mcp_config variable provided", async () => {
    const id = await runContainer("alpine");

    try {
      const mcp_config = JSON.stringify({
        servers: { demo: { url: "http://localhost:1234" } },
      });

      const state = await runTerraformApply(import.meta.dir, {
        ...defaultVariables,

        mcp_config,
      });

      const script = findResourceInstance(
        state,
        "coder_script",
        "vscode-desktop-mcp",
      ).script;

      const resp = await execContainer(id, ["sh", "-c", script]);
      if (resp.exitCode !== 0) {
        console.log(resp.stdout);
        console.log(resp.stderr);
      }
      expect(resp.exitCode).toBe(0);

      const content = await readFileContainer(
        id,
        `${defaultVariables.config_folder.replace("$HOME", "/root")}/mcp_config.json`,
      );
      expect(content).toBe(mcp_config);
    } finally {
      await removeContainer(id);
    }
  }, 10000);
});
