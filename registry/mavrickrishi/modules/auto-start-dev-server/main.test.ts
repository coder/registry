import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("auto-start-dev-server", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "test-agent-123",
  });

  it("validates scan_depth range", () => {
    const t1 = async () => {
      await runTerraformApply(import.meta.dir, {
        agent_id: "test-agent-123",
        scan_depth: "0",
      });
    };
    expect(t1).toThrow("Scan depth must be between 1 and 5");

    const t2 = async () => {
      await runTerraformApply(import.meta.dir, {
        agent_id: "test-agent-123",
        scan_depth: "6",
      });
    };
    expect(t2).toThrow("Scan depth must be between 1 and 5");
  });

  it("applies successfully with default values", async () => {
    await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent-123",
    });
  });

  it("applies successfully with all project types enabled", async () => {
    await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent-123",
      enable_npm: "true",
      enable_rails: "true",
      enable_django: "true",
      enable_flask: "true",
      enable_spring_boot: "true",
      enable_go: "true",
      enable_php: "true",
      enable_rust: "true",
      enable_dotnet: "true",
      enable_devcontainer: "true",
    });
  });

  it("applies successfully with all project types disabled", async () => {
    await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent-123",
      enable_npm: "false",
      enable_rails: "false",
      enable_django: "false",
      enable_flask: "false",
      enable_spring_boot: "false",
      enable_go: "false",
      enable_php: "false",
      enable_rust: "false",
      enable_dotnet: "false",
      enable_devcontainer: "false",
    });
  });

  it("applies successfully with custom configuration", async () => {
    await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent-123",
      workspace_directory: "/custom/workspace",
      scan_depth: "3",
      startup_delay: "5",
      log_path: "/var/log/custom-dev-servers.log",
      display_name: "Custom Dev Server Startup",
    });
  });

  it("validates scan_depth boundary values", async () => {
    // Test valid boundary values
    await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent-123",
      scan_depth: "1",
    });

    await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent-123", 
      scan_depth: "5",
    });
  });

  it("applies with selective project type configuration", async () => {
    await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent-123",
      enable_npm: "true",
      enable_django: "true",
      enable_go: "true",
      enable_rails: "false",
      enable_flask: "false",
      enable_spring_boot: "false",
      enable_php: "false", 
      enable_rust: "false",
      enable_dotnet: "false",
    });
  });
});