import { describe, expect, it } from "bun:test";
import {
  executeScriptInContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("restic", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "test-agent-id",
    repository: "s3:s3.amazonaws.com/test-bucket",
    password: "test-password",
  });

  it("installs restic successfully", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      repository: "/tmp/restic-repo",
      password: "test-password",
      install_restic: "true",
      auto_init_repo: "false",
      restore_on_start: "false",
    });

    const output = await executeScriptInContainer(
      state,
      "alpine",
      "sh",
      "apk add --no-cache curl bzip2",
    );

    if (output.exitCode !== 0) {
      console.log("Exit code:", output.exitCode);
      console.log("STDOUT:", output.stdout.join("\n"));
      console.log("STDERR:", output.stderr.join("\n"));
    }

    expect(output.exitCode).toBe(0);
    const stdout = output.stdout.join("\n");
    expect(stdout).toContain("Restic Backup Module Setup");
    expect(stdout).toContain("Installing Restic...");
    expect(stdout).toContain("Detected OS: linux");
    expect(stdout).toContain("Architecture:");
    expect(stdout).toContain("Fetching latest version");
    expect(stdout).toContain("Version:");
    expect(stdout).toContain("Downloading Restic");
    expect(stdout).toContain("Restic installed:");
    expect(stdout).toContain("Restic verified:");
    expect(stdout).toContain("restic");
    expect(stdout).toContain("Restic setup complete");
  });

  it("creates backup helper script in workspace", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      repository: "/tmp/restic-repo",
      password: "test-password",
      install_restic: "false",
      auto_init_repo: "false",
      restore_on_start: "false",
    });

    const output = await executeScriptInContainer(state, "alpine");

    const stdout = output.stdout.join("\n");

    expect(stdout).toContain("Installing backup helper script");
    expect(stdout).toContain("Backup helper installed:");
    expect(stdout).toContain("/restic-backup");
    expect(stdout).toContain("Backup helper verified as executable");
  });
});
