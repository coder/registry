import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("dev-server-autostart", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("applies with default values", async () => {
    await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
  });

  it("applies with custom configuration", async () => {
    await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      work_dir: "/workspace/my-project",
      scan_subdirectories: true,
      max_depth: 3,
      custom_commands: {
        "node": "npm run dev",
        "python": "uvicorn main:app --reload --host 0.0.0.0"
      },
      disabled_frameworks: ["php", "java"],
      devcontainer_integration: true,
      auto_install_deps: true,
      startup_delay: 10,
      health_check_enabled: false,
      log_level: "debug"
    });
  });

  it("validates max_depth parameter", () => {
    const t = async () => {
      await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        max_depth: 15, // Should fail validation (>10)
      });
    };
    expect(t).toThrow();
  });

  it("validates log_level parameter", () => {
    const t = async () => {
      await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        log_level: "invalid", // Should fail validation
      });
    };
    expect(t).toThrow();
  });

  it("validates startup_delay parameter", () => {
    const t = async () => {
      await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        startup_delay: 120, // Should fail validation (>60)
      });
    };
    expect(t).toThrow();
  });

  it("validates timeout_seconds parameter", () => {
    const t = async () => {
      await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        timeout_seconds: 2000, // Should fail validation (>1800)
      });
    };
    expect(t).toThrow();
  });
});
