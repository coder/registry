import { describe, expect, it } from "bun:test";
import { runTerraformApply, runTerraformInit } from "~test";

describe("gcp-disk-snapshot", async () => {
  await runTerraformInit(import.meta.dir);

  it("required variables with test mode", async () => {
    await runTerraformApply(import.meta.dir, {
      disk_self_link:
        "projects/test-project/zones/us-central1-a/disks/test-disk",
      default_image: "debian-cloud/debian-12",
      zone: "us-central1-a",
      project: "test-project",
      test_mode: true,
    });
  });

  it("missing variable: disk_self_link", async () => {
    await expect(
      runTerraformApply(import.meta.dir, {
        default_image: "debian-cloud/debian-12",
        zone: "us-central1-a",
        project: "test-project",
        test_mode: true,
      }),
    ).rejects.toThrow();
  });

  it("missing variable: default_image", async () => {
    await expect(
      runTerraformApply(import.meta.dir, {
        disk_self_link:
          "projects/test-project/zones/us-central1-a/disks/test-disk",
        zone: "us-central1-a",
        project: "test-project",
        test_mode: true,
      }),
    ).rejects.toThrow();
  });

  it("missing variable: zone", async () => {
    await expect(
      runTerraformApply(import.meta.dir, {
        disk_self_link:
          "projects/test-project/zones/us-central1-a/disks/test-disk",
        default_image: "debian-cloud/debian-12",
        project: "test-project",
        test_mode: true,
      }),
    ).rejects.toThrow();
  });

  it("missing variable: project", async () => {
    await expect(
      runTerraformApply(import.meta.dir, {
        disk_self_link:
          "projects/test-project/zones/us-central1-a/disks/test-disk",
        default_image: "debian-cloud/debian-12",
        zone: "us-central1-a",
        test_mode: true,
      }),
    ).rejects.toThrow();
  });

  it("supports optional variables", async () => {
    await runTerraformApply(import.meta.dir, {
      disk_self_link:
        "projects/test-project/zones/us-central1-a/disks/test-disk",
      default_image: "debian-cloud/debian-12",
      zone: "us-central1-a",
      project: "test-project",
      test_mode: true,
      storage_locations: JSON.stringify(["us-central1"]),
      labels: JSON.stringify({
        environment: "test",
        team: "engineering",
      }),
    });
  });
});
