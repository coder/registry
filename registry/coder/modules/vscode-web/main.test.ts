import {
  describe,
  expect,
  it,
  beforeAll,
  afterEach,
  setDefaultTimeout,
} from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  runContainer,
  execContainer,
  removeContainer,
  findResourceInstance,
} from "~test";

// Set timeout to 5 minutes for tests that download VS Code CLI
setDefaultTimeout(5 * 60 * 1000);

let cleanupContainers: string[] = [];

afterEach(async () => {
  for (const id of cleanupContainers) {
    try {
      await removeContainer(id);
    } catch {
      // Ignore cleanup errors
    }
  }
  cleanupContainers = [];
});

describe("vscode-web", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  describe("terraform validation", () => {
    it("accept_license should be set to true", async () => {
      try {
        await runTerraformApply(import.meta.dir, {
          agent_id: "foo",
          accept_license: false,
        });
        throw new Error("Expected terraform apply to fail");
      } catch (ex) {
        expect((ex as Error).message).toContain("Invalid value for variable");
      }
    });

    it("use_cached and offline can not be used together", async () => {
      try {
        await runTerraformApply(import.meta.dir, {
          agent_id: "foo",
          accept_license: true,
          use_cached: true,
          offline: true,
        });
        throw new Error("Expected terraform apply to fail");
      } catch (ex) {
        expect((ex as Error).message).toContain(
          "Offline and Use Cached can not be used together",
        );
      }
    });

    it("offline and extensions can not be used together", async () => {
      try {
        await runTerraformApply(import.meta.dir, {
          agent_id: "foo",
          accept_license: true,
          offline: true,
          extensions: '["ms-python.python"]',
        });
        throw new Error("Expected terraform apply to fail");
      } catch (ex) {
        expect((ex as Error).message).toContain(
          "Offline mode does not allow extensions to be installed",
        );
      }
    });

    it("workspace and folder can not be used together", async () => {
      try {
        await runTerraformApply(import.meta.dir, {
          agent_id: "foo",
          accept_license: true,
          folder: "/home/coder",
          workspace: "/home/coder/test.code-workspace",
        });
        throw new Error("Expected terraform apply to fail");
      } catch (ex) {
        expect((ex as Error).message).toContain(
          "Set only one of `workspace` or `folder`",
        );
      }
    });
  });

  describe("script generation", () => {
    it("generates script with correct port", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
        port: 8080,
      });
      const script = findResourceInstance(state, "coder_script");
      expect(script.script).toContain("--port 8080");
    });

    it("generates script with extensions directory", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
        extensions_dir: "/custom/extensions",
      });
      const script = findResourceInstance(state, "coder_script");
      expect(script.script).toContain("--extensions-dir=/custom/extensions");
    });

    it("generates script with telemetry level", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
        telemetry_level: "off",
      });
      const script = findResourceInstance(state, "coder_script");
      expect(script.script).toContain("--telemetry-level off");
    });

    it("generates script with disable trust", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
        disable_trust: true,
      });
      const script = findResourceInstance(state, "coder_script");
      expect(script.script).toContain("--disable-workspace-trust");
    });

    it("generates script with serve-web command", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
      });
      const script = findResourceInstance(state, "coder_script");
      expect(script.script).toContain("serve-web");
      expect(script.script).toContain("--accept-server-license-terms");
      expect(script.script).toContain("--without-connection-token");
    });

    it("generates script with stable release channel by default", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
      });
      const script = findResourceInstance(state, "coder_script");
      expect(script.script).toContain("build=stable");
    });

    it("generates script with insiders release channel", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
        release_channel: "insiders",
      });
      const script = findResourceInstance(state, "coder_script");
      expect(script.script).toContain("build=insiders");
    });

    it("generates script without commit-id value when not specified", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
      });
      const script = findResourceInstance(state, "coder_script");
      // The if condition should have an empty string, so no commit-id value is passed
      expect(script.script).toContain('if [ -n "" ]; then');
      // Should not contain any actual commit hash
      expect(script.script).not.toMatch(/--commit-id [a-f0-9]{40}/);
    });

    it("generates script with commit-id when specified", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
        commit_id: "e54c774e0add60467559eb0d1e229c6452cf8447",
      });
      const script = findResourceInstance(state, "coder_script");
      expect(script.script).toContain(
        "--commit-id e54c774e0add60467559eb0d1e229c6452cf8447",
      );
    });
  });

  describe("container integration tests", () => {
    it("uses existing code CLI in PATH", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
      });

      const containerId = await runContainer("ubuntu:22.04");
      cleanupContainers.push(containerId);

      // Create a mock code CLI that logs when serve-web is called
      await execContainer(containerId, [
        "bash",
        "-c",
        `cat > /usr/local/bin/code << 'MOCKEOF'
#!/bin/bash
if [ "\$1" = "serve-web" ]; then
  echo "MOCK_SERVER_STARTED with args: \$@"
  exit 0
fi
echo "code mock called: \$@"
exit 0
MOCKEOF
chmod +x /usr/local/bin/code`,
      ]);

      const script = findResourceInstance(state, "coder_script");

      // Run the script - the mock will capture the serve-web call
      const result = await execContainer(containerId, [
        "bash",
        "-c",
        script.script,
      ]);

      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain("Found VS Code CLI");
    });

    it("offline mode fails when CLI not present", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
        offline: true,
      });

      const containerId = await runContainer("ubuntu:22.04");
      cleanupContainers.push(containerId);

      const script = findResourceInstance(state, "coder_script");

      const result = await execContainer(containerId, [
        "bash",
        "-c",
        script.script,
      ]);

      expect(result.exitCode).toBe(1);
      expect(result.stdout).toContain(
        "Offline mode enabled but no VS Code CLI, code-server, or cached VS Code Server found",
      );
    });

    it("offline mode uses code-server as fallback", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
        offline: true,
      });

      const containerId = await runContainer("ubuntu:22.04");
      cleanupContainers.push(containerId);

      // Install mock code-server in PATH
      await execContainer(containerId, [
        "bash",
        "-c",
        `mkdir -p /usr/local/bin && cat > /usr/local/bin/code-server << 'MOCKEOF'
#!/bin/bash
echo "MOCK_CODE_SERVER_STARTED with args: $@"
exit 0
MOCKEOF
chmod +x /usr/local/bin/code-server`,
      ]);

      const script = findResourceInstance(state, "coder_script");

      const result = await execContainer(containerId, [
        "bash",
        "-c",
        script.script,
      ]);

      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain("offline fallback");
      expect(result.stdout).toContain("Starting code-server");
    });

    it("offline mode works with pre-installed CLI", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
        offline: true,
        install_prefix: "/tmp/vscode-web",
      });

      const containerId = await runContainer("ubuntu:22.04");
      cleanupContainers.push(containerId);

      // Pre-install mock code CLI at expected location
      await execContainer(containerId, [
        "bash",
        "-c",
        `mkdir -p /tmp/vscode-web/bin && cat > /tmp/vscode-web/bin/code << 'MOCKEOF'
#!/bin/bash
if [ "\$1" = "serve-web" ]; then
  echo "MOCK_OFFLINE_SERVER_STARTED"
  exit 0
fi
exit 0
MOCKEOF
chmod +x /tmp/vscode-web/bin/code`,
      ]);

      const script = findResourceInstance(state, "coder_script");

      const result = await execContainer(containerId, [
        "bash",
        "-c",
        script.script,
      ]);

      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain("Using cached VS Code CLI");
      expect(result.stdout).toContain("Starting VS Code Web");
    });

    it("use_cached mode works with pre-installed CLI", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
        use_cached: true,
        install_prefix: "/tmp/vscode-web",
      });

      const containerId = await runContainer("ubuntu:22.04");
      cleanupContainers.push(containerId);

      // Pre-install mock code CLI
      await execContainer(containerId, [
        "bash",
        "-c",
        `mkdir -p /tmp/vscode-web/bin && cat > /tmp/vscode-web/bin/code << 'MOCKEOF'
#!/bin/bash
if [ "\$1" = "serve-web" ]; then
  echo "MOCK_CACHED_SERVER_STARTED"
  exit 0
fi
exit 0
MOCKEOF
chmod +x /tmp/vscode-web/bin/code`,
      ]);

      const script = findResourceInstance(state, "coder_script");

      const result = await execContainer(containerId, [
        "bash",
        "-c",
        script.script,
      ]);

      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain("Using cached VS Code CLI");
    });

    it("creates settings file with correct content", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
        settings: '{"editor.fontSize": 14}',
      });

      const containerId = await runContainer("ubuntu:22.04");
      cleanupContainers.push(containerId);

      // Create a mock code CLI
      await execContainer(containerId, [
        "bash",
        "-c",
        `mkdir -p /usr/local/bin && cat > /usr/local/bin/code << 'MOCKEOF'
#!/bin/bash
exit 0
MOCKEOF
chmod +x /usr/local/bin/code`,
      ]);

      const script = findResourceInstance(state, "coder_script");

      await execContainer(containerId, ["bash", "-c", script.script]);

      // Check that settings file was created
      const settingsResult = await execContainer(containerId, [
        "cat",
        "/root/.vscode-server/data/Machine/settings.json",
      ]);

      expect(settingsResult.exitCode).toBe(0);
      expect(settingsResult.stdout).toContain("editor.fontSize");
      expect(settingsResult.stdout).toContain("14");
    });

    it("creates settings file with multiple settings", async () => {
      const settings = {
        "editor.fontSize": 16,
        "editor.tabSize": 2,
        "workbench.colorTheme": "Dracula",
        "editor.formatOnSave": true,
      };

      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
        settings: JSON.stringify(settings),
      });

      const containerId = await runContainer("ubuntu:22.04");
      cleanupContainers.push(containerId);

      // Create a mock code CLI
      await execContainer(containerId, [
        "bash",
        "-c",
        `mkdir -p /usr/local/bin && cat > /usr/local/bin/code << 'MOCKEOF'
#!/bin/bash
exit 0
MOCKEOF
chmod +x /usr/local/bin/code`,
      ]);

      const script = findResourceInstance(state, "coder_script");

      await execContainer(containerId, ["bash", "-c", script.script]);

      // Check that settings file was created with all settings
      const settingsResult = await execContainer(containerId, [
        "cat",
        "/root/.vscode-server/data/Machine/settings.json",
      ]);

      expect(settingsResult.exitCode).toBe(0);
      expect(settingsResult.stdout).toContain("editor.fontSize");
      expect(settingsResult.stdout).toContain("16");
      expect(settingsResult.stdout).toContain("editor.tabSize");
      expect(settingsResult.stdout).toContain("2");
      expect(settingsResult.stdout).toContain("workbench.colorTheme");
      expect(settingsResult.stdout).toContain("Dracula");
      expect(settingsResult.stdout).toContain("editor.formatOnSave");
      expect(settingsResult.stdout).toContain("true");
    });

    it("creates settings file in correct directory structure", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
        settings: '{"test.setting": "value"}',
      });

      const containerId = await runContainer("ubuntu:22.04");
      cleanupContainers.push(containerId);

      // Create a mock code CLI
      await execContainer(containerId, [
        "bash",
        "-c",
        `mkdir -p /usr/local/bin && cat > /usr/local/bin/code << 'MOCKEOF'
#!/bin/bash
exit 0
MOCKEOF
chmod +x /usr/local/bin/code`,
      ]);

      const script = findResourceInstance(state, "coder_script");

      await execContainer(containerId, ["bash", "-c", script.script]);

      // Verify directory structure was created
      const dirResult = await execContainer(containerId, [
        "ls",
        "-la",
        "/root/.vscode-server/data/Machine/",
      ]);

      expect(dirResult.exitCode).toBe(0);
      expect(dirResult.stdout).toContain("settings.json");

      // Verify parent directories exist
      const parentDirResult = await execContainer(containerId, [
        "ls",
        "-la",
        "/root/.vscode-server/data/",
      ]);

      expect(parentDirResult.exitCode).toBe(0);
      expect(parentDirResult.stdout).toContain("Machine");
    });

    it("does not overwrite existing settings file", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
        settings: '{"new.setting": "new_value"}',
      });

      const containerId = await runContainer("ubuntu:22.04");
      cleanupContainers.push(containerId);

      // Create a mock code CLI
      await execContainer(containerId, [
        "bash",
        "-c",
        `mkdir -p /usr/local/bin && cat > /usr/local/bin/code << 'MOCKEOF'
#!/bin/bash
exit 0
MOCKEOF
chmod +x /usr/local/bin/code`,
      ]);

      // Pre-create an existing settings file
      await execContainer(containerId, [
        "bash",
        "-c",
        `mkdir -p /root/.vscode-server/data/Machine && echo '{"existing.setting": "existing_value"}' > /root/.vscode-server/data/Machine/settings.json`,
      ]);

      const script = findResourceInstance(state, "coder_script");

      await execContainer(containerId, ["bash", "-c", script.script]);

      // Check that existing settings file was NOT overwritten
      const settingsResult = await execContainer(containerId, [
        "cat",
        "/root/.vscode-server/data/Machine/settings.json",
      ]);

      expect(settingsResult.exitCode).toBe(0);
      // Should contain existing setting, not the new one
      expect(settingsResult.stdout).toContain("existing.setting");
      expect(settingsResult.stdout).toContain("existing_value");
      expect(settingsResult.stdout).not.toContain("new.setting");
    });

    it("creates valid JSON settings file", async () => {
      const settings = {
        "editor.fontSize": 14,
        "editor.wordWrap": "on",
        "files.autoSave": "afterDelay",
        "files.autoSaveDelay": 1000,
      };

      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
        settings: JSON.stringify(settings),
      });

      const containerId = await runContainer("ubuntu:22.04");
      cleanupContainers.push(containerId);

      // Install jq and create mock code CLI
      await execContainer(containerId, ["apt-get", "update", "-qq"]);
      await execContainer(containerId, [
        "apt-get",
        "install",
        "-y",
        "-qq",
        "jq",
      ]);
      await execContainer(containerId, [
        "bash",
        "-c",
        `mkdir -p /usr/local/bin && cat > /usr/local/bin/code << 'MOCKEOF'
#!/bin/bash
exit 0
MOCKEOF
chmod +x /usr/local/bin/code`,
      ]);

      const script = findResourceInstance(state, "coder_script");

      await execContainer(containerId, ["bash", "-c", script.script]);

      // Validate JSON using jq
      const jsonValidResult = await execContainer(containerId, [
        "bash",
        "-c",
        "jq '.' /root/.vscode-server/data/Machine/settings.json",
      ]);

      expect(jsonValidResult.exitCode).toBe(0);

      // Extract specific values using jq
      const fontSizeResult = await execContainer(containerId, [
        "bash",
        "-c",
        "jq '.\"editor.fontSize\"' /root/.vscode-server/data/Machine/settings.json",
      ]);
      expect(fontSizeResult.stdout.trim()).toBe("14");

      const wordWrapResult = await execContainer(containerId, [
        "bash",
        "-c",
        "jq '.\"editor.wordWrap\"' /root/.vscode-server/data/Machine/settings.json",
      ]);
      expect(wordWrapResult.stdout.trim()).toBe('"on"');

      const autoSaveDelayResult = await execContainer(containerId, [
        "bash",
        "-c",
        "jq '.\"files.autoSaveDelay\"' /root/.vscode-server/data/Machine/settings.json",
      ]);
      expect(autoSaveDelayResult.stdout.trim()).toBe("1000");
    });

    it("installs extensions", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
        extensions: '["ms-python.python", "golang.go"]',
      });

      const containerId = await runContainer("ubuntu:22.04");
      cleanupContainers.push(containerId);

      // Create a mock code CLI that logs extension installs
      await execContainer(containerId, [
        "bash",
        "-c",
        `mkdir -p /usr/local/bin && cat > /usr/local/bin/code << 'MOCKEOF'
#!/bin/bash
if [ "\$1" = "--install-extension" ]; then
  echo "MOCK_EXTENSION_INSTALL: \$2"
fi
exit 0
MOCKEOF
chmod +x /usr/local/bin/code`,
      ]);

      const script = findResourceInstance(state, "coder_script");

      const result = await execContainer(containerId, [
        "bash",
        "-c",
        script.script,
      ]);

      expect(result.exitCode).toBe(0);
      expect(result.stdout).toContain("Installing extension");
      expect(result.stdout).toContain("ms-python.python");
      expect(result.stdout).toContain("golang.go");
    });

    it("runs with correct server arguments", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
        port: 9999,
        telemetry_level: "off",
      });

      const containerId = await runContainer("ubuntu:22.04");
      cleanupContainers.push(containerId);

      // Create a mock code CLI that captures all arguments
      await execContainer(containerId, [
        "bash",
        "-c",
        `mkdir -p /usr/local/bin && cat > /usr/local/bin/code << 'MOCKEOF'
#!/bin/bash
echo "MOCK_CODE_ARGS: \$@"
exit 0
MOCKEOF
chmod +x /usr/local/bin/code`,
      ]);

      const script = findResourceInstance(state, "coder_script");

      const result = await execContainer(containerId, [
        "bash",
        "-c",
        script.script,
      ]);

      expect(result.exitCode).toBe(0);
      // Check the output contains expected port message
      expect(result.stdout).toContain("Starting VS Code Web on port 9999");
    });

    it("passes commit-id to code CLI when specified", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
        commit_id: "abc123def456",
      });

      const containerId = await runContainer("ubuntu:22.04");
      cleanupContainers.push(containerId);

      // Create a mock code CLI that logs arguments to the log file (where output is redirected)
      await execContainer(containerId, [
        "bash",
        "-c",
        `mkdir -p /usr/local/bin && cat > /usr/local/bin/code << 'MOCKEOF'
#!/bin/bash
echo "MOCK_CODE_ARGS: $@"
exit 0
MOCKEOF
chmod +x /usr/local/bin/code`,
      ]);

      const script = findResourceInstance(state, "coder_script");

      await execContainer(containerId, ["bash", "-c", script.script]);

      // Wait briefly for background process to write to log
      await new Promise((resolve) => setTimeout(resolve, 500));

      // Check the log file for the arguments (code CLI output goes there)
      const logResult = await execContainer(containerId, [
        "cat",
        "/tmp/vscode-web.log",
      ]);

      expect(logResult.exitCode).toBe(0);
      expect(logResult.stdout).toContain("--commit-id abc123def456");
    });

    // This test downloads and starts the real VS Code server
    it("starts real VS Code CLI and responds to healthcheck (requires network)", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        accept_license: true,
        port: 13338,
        install_prefix: "/tmp/vscode-web",
      });

      const containerId = await runContainer("ubuntu:22.04");
      cleanupContainers.push(containerId);

      // Install curl for downloading CLI and healthcheck
      await execContainer(containerId, ["apt-get", "update", "-qq"]);
      await execContainer(containerId, [
        "apt-get",
        "install",
        "-y",
        "-qq",
        "curl",
      ]);

      const script = findResourceInstance(state, "coder_script");

      // Run the script - it will start the server in background
      const startResult = await execContainer(containerId, [
        "bash",
        "-c",
        script.script,
      ]);

      expect(startResult.exitCode).toBe(0);
      expect(startResult.stdout).toContain("Starting VS Code Web");

      // Wait for server to start and check healthcheck
      await new Promise((resolve) => setTimeout(resolve, 10000));

      const healthResult = await execContainer(containerId, [
        "curl",
        "-s",
        "-o",
        "/dev/null",
        "-w",
        "%{http_code}",
        "http://127.0.0.1:13338/healthz",
      ]);

      // Server should respond (200, 202, or 404 is acceptable - means server is running)
      expect(["200", "202", "404"]).toContain(healthResult.stdout.trim());
    });
  });
});
