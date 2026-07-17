import { spawn } from "bun";
import { beforeAll, describe, expect, it } from "bun:test";
import {
  executeScriptInContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

// Image used by every container-based test below. Pulling it the first time a
// test runs can exceed the per-test timeout, so pre-pull it once up front.
const TEST_IMAGE = "ubuntu:20.04";

describe("nexus-repository", async () => {
  await runTerraformInit(import.meta.dir);

  // Warm the Docker image cache before any container test runs so the one-time
  // pull cost isn't charged against (and doesn't time out) the first test.
  beforeAll(async () => {
    const proc = spawn(["docker", "pull", TEST_IMAGE], {
      stdout: "ignore",
      stderr: "ignore",
    });
    await proc.exited;
  }, 300_000);

  testRequiredVariables(import.meta.dir, {
    agent_id: "test-agent",
    nexus_url: "https://nexus.example.com",
    nexus_password: "test-password",
  });

  it("configures Maven settings", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      nexus_url: "https://nexus.example.com",
      nexus_password: "test-token",
      package_managers: JSON.stringify({
        maven: ["maven-public"],
      }),
    });

    const output = await executeScriptInContainer(state, TEST_IMAGE);
    expect(output.stdout.join("\n")).toContain("☕ Configuring Maven...");
    expect(output.stdout.join("\n")).toContain("🥳 Configuration complete!");
  });

  it("configures npm registry", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      nexus_url: "https://nexus.example.com",
      nexus_password: "test-token",
      package_managers: JSON.stringify({
        npm: ["npm-public"],
      }),
    });

    const output = await executeScriptInContainer(state, TEST_IMAGE);
    expect(output.stdout.join("\n")).toContain("📦 Configuring npm...");
    expect(output.stdout.join("\n")).toContain("🥳 Configuration complete!");
  });

  it("configures PyPI repository", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      nexus_url: "https://nexus.example.com",
      nexus_password: "test-token",
      package_managers: JSON.stringify({
        pypi: ["pypi-public"],
      }),
    });

    const output = await executeScriptInContainer(state, TEST_IMAGE);
    expect(output.stdout.join("\n")).toContain("🐍 Configuring pip...");
    expect(output.stdout.join("\n")).toContain("🥳 Configuration complete!");
  });

  it("configures multiple package managers", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      nexus_url: "https://nexus.example.com",
      nexus_password: "test-token",
      package_managers: JSON.stringify({
        maven: ["maven-public"],
        npm: ["npm-public"],
        pypi: ["pypi-public"],
      }),
    });

    const output = await executeScriptInContainer(state, TEST_IMAGE);
    expect(output.stdout.join("\n")).toContain("☕ Configuring Maven...");
    expect(output.stdout.join("\n")).toContain("📦 Configuring npm...");
    expect(output.stdout.join("\n")).toContain("🐍 Configuring pip...");
    expect(output.stdout.join("\n")).toContain(
      "✅ Nexus repository configuration completed!",
    );
  });

  it("handles empty package managers", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      nexus_url: "https://nexus.example.com",
      nexus_password: "test-token",
      package_managers: JSON.stringify({}),
    });

    const output = await executeScriptInContainer(state, TEST_IMAGE);
    expect(output.stdout.join("\n")).toContain(
      "🤔 no maven repository is set, skipping maven configuration.",
    );
    expect(output.stdout.join("\n")).toContain(
      "🤔 no npm repository is set, skipping npm configuration.",
    );
    expect(output.stdout.join("\n")).toContain(
      "🤔 no pypi repository is set, skipping pypi configuration.",
    );
    expect(output.stdout.join("\n")).toContain(
      "🤔 no docker repository is set, skipping docker configuration.",
    );
  });

  it("configures Go module proxy", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      nexus_url: "https://nexus.example.com",
      nexus_password: "test-token",
      package_managers: JSON.stringify({
        go: ["go-public", "go-private"],
      }),
    });

    const output = await executeScriptInContainer(state, TEST_IMAGE);
    expect(output.stdout.join("\n")).toContain("🐹 Configuring Go...");
    expect(output.stdout.join("\n")).toContain(
      "Go proxy configured via GOPROXY environment variable",
    );
    expect(output.stdout.join("\n")).toContain("🥳 Configuration complete!");
  });

  it("validates nexus_url format", async () => {
    await expect(
      runTerraformApply(import.meta.dir, {
        agent_id: "test-agent",
        nexus_url: "invalid-url",
        nexus_password: "test-token",
        package_managers: JSON.stringify({}),
      }),
    ).rejects.toThrow();
  });

  it("validates username_field values", async () => {
    await expect(
      runTerraformApply(import.meta.dir, {
        agent_id: "test-agent",
        nexus_url: "https://nexus.example.com",
        nexus_password: "test-token",
        username_field: "invalid",
        package_managers: JSON.stringify({}),
      }),
    ).rejects.toThrow();
  });
});
