import { describe, expect, it } from "bun:test";
import {
  executeScriptInContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("nexus", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "test-agent",
    nexus_url: "https://nexus.example.com", 
    nexus_password: "test-password"
  });

  it("configures Maven settings", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      nexus_url: "https://nexus.example.com",
      nexus_password: "test-token",
      package_managers: JSON.stringify({
        maven: ["maven-public"]
      })
    });

    const output = await executeScriptInContainer(state, "ubuntu:20.04");
    expect(output.stdout.join("\n")).toContain("☕ Configuring Maven...");
    expect(output.stdout.join("\n")).toContain("🥳 Configuration complete!");
  });

  it("configures npm registry", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      nexus_url: "https://nexus.example.com", 
      nexus_password: "test-token",
      package_managers: JSON.stringify({
        npm: ["npm-public"]
      })
    });

    const output = await executeScriptInContainer(state, "ubuntu:20.04");
    expect(output.stdout.join("\n")).toContain("📦 Configuring npm...");
    expect(output.stdout.join("\n")).toContain("🥳 Configuration complete!");
  });

  it("configures PyPI repository", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      nexus_url: "https://nexus.example.com",
      nexus_password: "test-token", 
      package_managers: JSON.stringify({
        pypi: ["pypi-public"]
      })
    });

    const output = await executeScriptInContainer(state, "ubuntu:20.04");
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
        pypi: ["pypi-public"]
      })
    });

    const output = await executeScriptInContainer(state, "ubuntu:20.04");
    expect(output.stdout.join("\n")).toContain("☕ Configuring Maven...");
    expect(output.stdout.join("\n")).toContain("📦 Configuring npm...");
    expect(output.stdout.join("\n")).toContain("🐍 Configuring pip...");
    expect(output.stdout.join("\n")).toContain("✅ Nexus repository configuration completed!");
  });

  it("handles empty package managers", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      nexus_url: "https://nexus.example.com",
      nexus_password: "test-token",
      package_managers: JSON.stringify({})
    });

    const output = await executeScriptInContainer(state, "ubuntu:20.04");
    expect(output.stdout.join("\n")).toContain("🤔 no maven repository is set, skipping maven configuration.");
    expect(output.stdout.join("\n")).toContain("🤔 no npm repository is set, skipping npm configuration.");
    expect(output.stdout.join("\n")).toContain("🤔 no pypi repository is set, skipping pypi configuration.");
    expect(output.stdout.join("\n")).toContain("🤔 no docker repository is set, skipping docker configuration.");
  });

  it("validates nexus_url format", async () => {
    await expect(
      runTerraformApply(import.meta.dir, {
        agent_id: "test-agent",
        nexus_url: "invalid-url",
        nexus_password: "test-token",
        package_managers: JSON.stringify({})
      })
    ).rejects.toThrow();
  });

  it("validates username_field values", async () => {
    await expect(
      runTerraformApply(import.meta.dir, {
        agent_id: "test-agent", 
        nexus_url: "https://nexus.example.com",
        nexus_password: "test-token",
        username_field: "invalid",
        package_managers: JSON.stringify({})
      })
    ).rejects.toThrow();
  });
});