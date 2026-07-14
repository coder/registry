import {
  describe,
  expect,
  it,
  beforeAll,
  afterEach,
  setDefaultTimeout,
} from "bun:test";
import {
  execContainer,
  findResourceInstance,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

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

describe("code-server", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("use_cached and offline can not be used together", () => {
    const t = async () => {
      await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
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
        offline: "true",
        extensions: '["1", "2"]',
      });
    };
    expect(t).toThrow("Offline mode does not allow extensions to be installed");
  });

  it("creates user settings file with correct content", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      offline: true,
      settings: '{"editor.fontSize": 14}',
    });

    const containerId = await runContainer("ubuntu:22.04");
    cleanupContainers.push(containerId);

    // Create a mock code-server CLI
    await execContainer(containerId, [
      "bash",
      "-c",
      `mkdir -p /tmp/code-server/bin && cat > /tmp/code-server/bin/code-server << 'MOCKEOF'
#!/bin/bash
if [ "$1" = "--list-extensions" ]; then
  exit 0
fi
echo "Mock code-server running"
exit 0
MOCKEOF
chmod +x /tmp/code-server/bin/code-server`,
    ]);

    const script = findResourceInstance(state, "coder_script");

    const scriptResult = await execContainer(containerId, [
      "bash",
      "-c",
      script.script,
    ]);
    expect(scriptResult.exitCode).toBe(0);

    const settingsResult = await execContainer(containerId, [
      "cat",
      "/root/.local/share/code-server/User/settings.json",
    ]);

    expect(settingsResult.exitCode).toBe(0);
    expect(settingsResult.stdout).toContain("editor.fontSize");
    expect(settingsResult.stdout).toContain("14");
  });

  it("merges user settings with existing settings file", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      offline: true,
      settings: '{"new.setting": "new_value"}',
    });

    const containerId = await runContainer("ubuntu:22.04");
    cleanupContainers.push(containerId);

    await execContainer(containerId, ["apt-get", "update", "-qq"]);
    await execContainer(containerId, ["apt-get", "install", "-y", "-qq", "jq"]);
    await execContainer(containerId, [
      "bash",
      "-c",
      `mkdir -p /tmp/code-server/bin && cat > /tmp/code-server/bin/code-server << 'MOCKEOF'
#!/bin/bash
if [ "$1" = "--list-extensions" ]; then
  exit 0
fi
echo "Mock code-server running"
exit 0
MOCKEOF
chmod +x /tmp/code-server/bin/code-server`,
    ]);

    // Pre-create an existing settings file
    await execContainer(containerId, [
      "bash",
      "-c",
      `mkdir -p /root/.local/share/code-server/User && echo '{"existing.setting": "existing_value"}' > /root/.local/share/code-server/User/settings.json`,
    ]);

    const script = findResourceInstance(state, "coder_script");

    const scriptResult = await execContainer(containerId, [
      "bash",
      "-c",
      script.script,
    ]);
    expect(scriptResult.exitCode).toBe(0);

    const settingsResult = await execContainer(containerId, [
      "cat",
      "/root/.local/share/code-server/User/settings.json",
    ]);

    expect(settingsResult.exitCode).toBe(0);
    expect(settingsResult.stdout).toContain("existing.setting");
    expect(settingsResult.stdout).toContain("existing_value");
    expect(settingsResult.stdout).toContain("new.setting");
    expect(settingsResult.stdout).toContain("new_value");
  });

  it("merges machine settings with existing settings file", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      offline: true,
      machine_settings: '{"template.setting": "template_value"}',
    });

    const containerId = await runContainer("ubuntu:22.04");
    cleanupContainers.push(containerId);

    await execContainer(containerId, ["apt-get", "update", "-qq"]);
    await execContainer(containerId, ["apt-get", "install", "-y", "-qq", "jq"]);
    await execContainer(containerId, [
      "bash",
      "-c",
      `mkdir -p /tmp/code-server/bin && cat > /tmp/code-server/bin/code-server << 'MOCKEOF'
#!/bin/bash
if [ "$1" = "--list-extensions" ]; then
  exit 0
fi
echo "Mock code-server running"
exit 0
MOCKEOF
chmod +x /tmp/code-server/bin/code-server`,
    ]);

    // Pre-create an existing Machine settings file
    await execContainer(containerId, [
      "bash",
      "-c",
      `mkdir -p /root/.local/share/code-server/Machine && echo '{"existing.machine": "machine_value"}' > /root/.local/share/code-server/Machine/settings.json`,
    ]);

    const script = findResourceInstance(state, "coder_script");

    const scriptResult = await execContainer(containerId, [
      "bash",
      "-c",
      script.script,
    ]);
    expect(scriptResult.exitCode).toBe(0);

    const settingsResult = await execContainer(containerId, [
      "cat",
      "/root/.local/share/code-server/Machine/settings.json",
    ]);

    expect(settingsResult.exitCode).toBe(0);
    expect(settingsResult.stdout).toContain("existing.machine");
    expect(settingsResult.stdout).toContain("machine_value");
    expect(settingsResult.stdout).toContain("template.setting");
    expect(settingsResult.stdout).toContain("template_value");
  });

  it("installs and runs code-server", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });

    const id = await runContainer("ubuntu:latest");
    cleanupContainers.push(id);

    await execContainer(id, [
      "bash",
      "-c",
      "apt-get update && apt-get install -y curl",
    ]);

    const script = findResourceInstance(state, "coder_script").script;
    const result = await execContainer(id, ["bash", "-c", script]);
    if (result.exitCode !== 0) {
      console.log(result.stdout);
      console.log(result.stderr);
    }
    expect(result.exitCode).toBe(0);

    const version = await execContainer(id, [
      "/tmp/code-server/bin/code-server",
      "--version",
    ]);
    expect(version.exitCode).toBe(0);
    expect(version.stdout).toMatch(/\d+\.\d+\.\d+/);

    const health = await execContainer(id, [
      "curl",
      "--retry",
      "10",
      "--retry-delay",
      "1",
      "--retry-all-errors",
      "-sf",
      "http://localhost:13337/healthz",
    ]);
    expect(health.exitCode).toBe(0);
  }, 60000);
});
