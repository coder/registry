import { describe, expect, it, setDefaultTimeout } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  runContainer,
  execContainer,
  removeContainer,
  findResourceInstance,
  readFileContainer,
  writeFileContainer,
} from "~test";

setDefaultTimeout(60 * 1000);

// hardcoded coder_app name in main.tf
const appName = "vscode-desktop";

const defaultVariables = {
  agent_id: "foo",

  coder_app_icon: "/icon/code.svg",
  coder_app_slug: "vscode",
  coder_app_display_name: "VS Code Desktop",

  protocol: "vscode",
  config_dir: "$HOME/.vscode",
};

const setupVariables = {
  ...defaultVariables,
  extensions: JSON.stringify([
    "ms-python.python",
    "esbenp.prettier-vscode@12.4.0",
  ]),
  extensions_dir: "$HOME/.ide-server/extensions",
  ide_cli_path: "/tmp/fake-ide-cli",
  ide_cli_install_script: "#!/usr/bin/env bash\nprintf 'bootstrap complete\\n'",
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
          open_recent: "false",

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
        `${defaultVariables.config_dir.replace("$HOME", "/root")}/mcp_config.json`,
      );
      expect(content).toBe(mcp_config);
    } finally {
      await removeContainer(id);
    }
  });

  describe("extension installation", () => {
    it("creates no extension script with default inputs", async () => {
      const state = await runTerraformApply(import.meta.dir, defaultVariables);

      const extensionScripts = state.resources.filter(
        (resource) =>
          resource.type === "coder_script" &&
          resource.name === "install_extensions",
      );

      expect(extensionScripts).toHaveLength(0);
    });

    it("creates one finite login-blocking script with wrapper-controlled inputs", async () => {
      const state = await runTerraformApply(import.meta.dir, setupVariables);
      const extensionInstaller = findResourceInstance(
        state,
        "coder_script",
        "install_extensions",
      );

      expect(extensionInstaller.run_on_start).toBe(true);
      expect(extensionInstaller.start_blocks_login).toBe(true);
      expect(extensionInstaller.timeout).toBe(1800);
      expect(extensionInstaller.script).toContain(
        Buffer.from(setupVariables.ide_cli_path).toString("base64"),
      );
      expect(extensionInstaller.script).toContain(
        Buffer.from(setupVariables.extensions_dir).toString("base64"),
      );
      expect(extensionInstaller.script).toContain(
        Buffer.from(setupVariables.ide_cli_install_script).toString("base64"),
      );
      expect(extensionInstaller.script).not.toContain(".vscode-server");
      expect(extensionInstaller.script).not.toContain(".cursor-server");
      expect(extensionInstaller.script).not.toContain(".windsurf-server");
    });

    it("installs each extension separately and remains idempotent", async () => {
      const state = await runTerraformApply(import.meta.dir, setupVariables);
      const setupScript = findResourceInstance(
        state,
        "coder_script",
        "install_extensions",
      ).script;
      const id = await runContainer("node:22-bookworm-slim");

      try {
        await writeFileContainer(
          id,
          setupVariables.ide_cli_path,
          `#!/bin/sh
printf '%s\\n' "$@" >> /tmp/ide-cli-args
`,
          { user: "root" },
        );
        await execContainer(
          id,
          ["chmod", "755", setupVariables.ide_cli_path],
          ["--user", "root"],
        );

        const firstRun = await execContainer(id, ["bash", "-c", setupScript]);
        expect(firstRun.exitCode).toBe(0);
        expect(firstRun.stdout).toContain("bootstrap complete");

        const secondRun = await execContainer(id, ["bash", "-c", setupScript]);
        expect(secondRun.exitCode).toBe(0);

        const argumentsLog = await readFileContainer(id, "/tmp/ide-cli-args");
        const expectedRun = [
          "--install-extension",
          "ms-python.python",
          "--extensions-dir",
          "/root/.ide-server/extensions",
          "--install-extension",
          "esbenp.prettier-vscode@12.4.0",
          "--extensions-dir",
          "/root/.ide-server/extensions",
        ];
        expect(argumentsLog.trim().split("\n")).toEqual([
          ...expectedRun,
          ...expectedRun,
        ]);
      } finally {
        await removeContainer(id);
      }
    }, 20000);

    it("fails clearly when the IDE CLI rejects an extension", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        ...setupVariables,
        extensions: JSON.stringify(["invalid.extension"]),
      });
      const setupScript = findResourceInstance(
        state,
        "coder_script",
        "install_extensions",
      ).script;
      const id = await runContainer("node:22-bookworm-slim");

      try {
        await writeFileContainer(
          id,
          setupVariables.ide_cli_path,
          `#!/bin/sh
printf 'extension installation failed\\n' >&2
exit 23
`,
          { user: "root" },
        );
        await execContainer(
          id,
          ["chmod", "755", setupVariables.ide_cli_path],
          ["--user", "root"],
        );

        const result = await execContainer(id, ["bash", "-c", setupScript]);
        expect(result.exitCode).toBe(23);
        expect(result.stdout).toContain(
          "Installing extension invalid.extension...",
        );
        expect(result.stderr).toContain("extension installation failed");
      } finally {
        await removeContainer(id);
      }
    }, 20000);

    it("fails before bootstrap when a required wrapper path is empty", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        ...setupVariables,
        extensions_dir: "",
        ide_cli_install_script: "touch /tmp/bootstrap-ran",
      });
      const setupScript = findResourceInstance(
        state,
        "coder_script",
        "install_extensions",
      ).script;
      const id = await runContainer("node:22-bookworm-slim");

      try {
        const result = await execContainer(id, ["bash", "-c", setupScript]);
        expect(result.exitCode).toBe(1);
        expect(result.stderr).toContain(
          "extensions_dir is required when extensions are configured.",
        );

        const bootstrapMarker = await execContainer(id, [
          "test",
          "!",
          "-e",
          "/tmp/bootstrap-ran",
        ]);
        expect(bootstrapMarker.exitCode).toBe(0);
      } finally {
        await removeContainer(id);
      }
    }, 20000);
  });
});
