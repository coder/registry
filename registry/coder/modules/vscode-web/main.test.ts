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

// Set timeout to 2 minutes for tests that install packages
setDefaultTimeout(2 * 60 * 1000);

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

  it("creates settings file with correct content", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      accept_license: true,
      use_cached: true,
      settings: '{"editor.fontSize": 14}',
    });

    const containerId = await runContainer("ubuntu:22.04");
    cleanupContainers.push(containerId);

    // Create a mock code-server CLI that the script expects
    await execContainer(containerId, [
      "bash",
      "-c",
      `mkdir -p /tmp/vscode-web/bin && cat > /tmp/vscode-web/bin/code-server << 'MOCKEOF'
#!/bin/bash
echo "Mock code-server running"
exit 0
MOCKEOF
chmod +x /tmp/vscode-web/bin/code-server`,
    ]);

    const script = findResourceInstance(state, "coder_script");

    const scriptResult = await execContainer(containerId, [
      "bash",
      "-c",
      script.script,
    ]);
    expect(scriptResult.exitCode).toBe(0);

    // Check that settings file was created
    const settingsResult = await execContainer(containerId, [
      "cat",
      "/root/.vscode-server/data/Machine/settings.json",
    ]);

    expect(settingsResult.exitCode).toBe(0);
    expect(settingsResult.stdout).toContain("editor.fontSize");
    expect(settingsResult.stdout).toContain("14");
  });

  it("merges settings with existing settings file", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      accept_license: true,
      use_cached: true,
      settings: '{"new.setting": "new_value"}',
    });

    const containerId = await runContainer("ubuntu:22.04");
    cleanupContainers.push(containerId);

    // Install jq and create mock code-server CLI
    await execContainer(containerId, ["apt-get", "update", "-qq"]);
    await execContainer(containerId, ["apt-get", "install", "-y", "-qq", "jq"]);
    await execContainer(containerId, [
      "bash",
      "-c",
      `mkdir -p /tmp/vscode-web/bin && cat > /tmp/vscode-web/bin/code-server << 'MOCKEOF'
#!/bin/bash
echo "Mock code-server running"
exit 0
MOCKEOF
chmod +x /tmp/vscode-web/bin/code-server`,
    ]);

    // Pre-create an existing settings file
    await execContainer(containerId, [
      "bash",
      "-c",
      `mkdir -p /root/.vscode-server/data/Machine && echo '{"existing.setting": "existing_value"}' > /root/.vscode-server/data/Machine/settings.json`,
    ]);

    const script = findResourceInstance(state, "coder_script");

    const scriptResult = await execContainer(containerId, [
      "bash",
      "-c",
      script.script,
    ]);
    expect(scriptResult.exitCode).toBe(0);

    // Check that settings were merged (both existing and new should be present)
    const settingsResult = await execContainer(containerId, [
      "cat",
      "/root/.vscode-server/data/Machine/settings.json",
    ]);

    expect(settingsResult.exitCode).toBe(0);
    // Should contain both existing and new settings
    expect(settingsResult.stdout).toContain("existing.setting");
    expect(settingsResult.stdout).toContain("existing_value");
    expect(settingsResult.stdout).toContain("new.setting");
    expect(settingsResult.stdout).toContain("new_value");
  });

  it("merges settings using python3 fallback when jq unavailable", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      accept_license: true,
      use_cached: true,
      settings: '{"new.setting": "new_value"}',
    });

    const containerId = await runContainer("ubuntu:22.04");
    cleanupContainers.push(containerId);

    // Install python3 (ubuntu:22.04 doesn't have it by default)
    await execContainer(containerId, ["apt-get", "update", "-qq"]);
    await execContainer(containerId, [
      "apt-get",
      "install",
      "-y",
      "-qq",
      "python3",
    ]);

    // Create mock code-server CLI (no jq installed)
    await execContainer(containerId, [
      "bash",
      "-c",
      `mkdir -p /tmp/vscode-web/bin && cat > /tmp/vscode-web/bin/code-server << 'MOCKEOF'
#!/bin/bash
echo "Mock code-server running"
exit 0
MOCKEOF
chmod +x /tmp/vscode-web/bin/code-server`,
    ]);

    // Pre-create an existing settings file
    await execContainer(containerId, [
      "bash",
      "-c",
      `mkdir -p /root/.vscode-server/data/Machine && echo '{"existing.setting": "existing_value"}' > /root/.vscode-server/data/Machine/settings.json`,
    ]);

    const script = findResourceInstance(state, "coder_script");

    const scriptResult = await execContainer(containerId, [
      "bash",
      "-c",
      script.script,
    ]);
    expect(scriptResult.exitCode).toBe(0);

    // Check that settings were merged using python3 fallback
    const settingsResult = await execContainer(containerId, [
      "cat",
      "/root/.vscode-server/data/Machine/settings.json",
    ]);

    expect(settingsResult.exitCode).toBe(0);
    // Should contain both existing and new settings
    expect(settingsResult.stdout).toContain("existing.setting");
    expect(settingsResult.stdout).toContain("existing_value");
    expect(settingsResult.stdout).toContain("new.setting");
    expect(settingsResult.stdout).toContain("new_value");
  });

  it("preserves existing settings when neither jq nor python3 available", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      accept_license: true,
      use_cached: true,
      settings: '{"new.setting": "new_value"}',
    });

    // Use ubuntu without installing jq or python3 (neither available by default)
    const containerId = await runContainer("ubuntu:22.04");
    cleanupContainers.push(containerId);

    // Create mock code-server CLI
    await execContainer(containerId, [
      "bash",
      "-c",
      `mkdir -p /tmp/vscode-web/bin && cat > /tmp/vscode-web/bin/code-server << 'MOCKEOF'
#!/bin/bash
echo "Mock code-server running"
exit 0
MOCKEOF
chmod +x /tmp/vscode-web/bin/code-server`,
    ]);

    // Pre-create an existing settings file
    await execContainer(containerId, [
      "bash",
      "-c",
      `mkdir -p /root/.vscode-server/data/Machine && echo '{"existing.setting": "existing_value"}' > /root/.vscode-server/data/Machine/settings.json`,
    ]);

    const script = findResourceInstance(state, "coder_script");

    // Run script - should warn but not fail
    const scriptResult = await execContainer(containerId, [
      "bash",
      "-c",
      script.script,
    ]);
    expect(scriptResult.exitCode).toBe(0);
    expect(scriptResult.stdout).toContain("Could not merge settings");

    // Existing settings should be preserved (not overwritten)
    const settingsResult = await execContainer(containerId, [
      "cat",
      "/root/.vscode-server/data/Machine/settings.json",
    ]);

    expect(settingsResult.exitCode).toBe(0);
    expect(settingsResult.stdout).toContain("existing.setting");
    expect(settingsResult.stdout).toContain("existing_value");
    expect(settingsResult.stdout).not.toContain("new.setting");
    expect(settingsResult.stdout).not.toContain("new_value");
  });
});
