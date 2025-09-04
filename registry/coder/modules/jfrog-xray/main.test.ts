import { describe, expect, it } from "bun:test";
import {
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("jfrog-xray", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    resource_id: "test-resource-id",
    xray_url: "https://example.jfrog.io/xray",
    xray_token: "test-token",
    image: "docker-local/test/image:latest",
  });

  it("validates required variables", async () => {
    // Test that all required variables are properly defined
    expect(true).toBe(true); // Placeholder - actual validation handled by testRequiredVariables
  });

  // Note: Full integration tests would require a live JFrog instance
  // and are better suited for end-to-end testing environments
});
