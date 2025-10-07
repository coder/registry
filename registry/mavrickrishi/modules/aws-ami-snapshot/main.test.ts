import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("aws-ami-snapshot", async () => {
  await runTerraformInit(import.meta.dir);

  it("required variables with test mode", async () => {
    await runTerraformApply(import.meta.dir, {
      instance_id: "i-1234567890abcdef0",
      default_ami_id: "ami-12345678",
      template_name: "test-template",
      test_mode: true,
    });
  });

  it("missing variable: instance_id", async () => {
    await expect(
      runTerraformApply(import.meta.dir, {
        default_ami_id: "ami-12345678",
        template_name: "test-template",
        test_mode: true,
      }),
    ).rejects.toThrow();
  });

  it("missing variable: default_ami_id", async () => {
    await expect(
      runTerraformApply(import.meta.dir, {
        instance_id: "i-1234567890abcdef0",
        template_name: "test-template",
        test_mode: true,
      }),
    ).rejects.toThrow();
  });

  it("missing variable: template_name", async () => {
    await expect(
      runTerraformApply(import.meta.dir, {
        instance_id: "i-1234567890abcdef0",
        default_ami_id: "ami-12345678",
        test_mode: true,
      }),
    ).rejects.toThrow();
  });

  it("supports optional variables", async () => {
    await runTerraformApply(import.meta.dir, {
      instance_id: "i-1234567890abcdef0",
      default_ami_id: "ami-12345678",
      template_name: "test-template",
      test_mode: true,
      enable_dlm_cleanup: true,
      dlm_role_arn: "arn:aws:iam::123456789012:role/dlm-lifecycle-role",
      snapshot_retention_count: 5,
      tags: JSON.stringify({
        Environment: "test",
        Project: "coder",
      }),
    });
  });
});
