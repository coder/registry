import { serve } from "bun";
import { describe, expect, it } from "bun:test";
import {
  createJSONResponse,
  findResourceInstance,
  runTerraformInit,
  runTerraformApply,
  testRequiredVariables,
} from "~test";

describe("jfrog-xray", async () => {
  await runTerraformInit(import.meta.dir);

  const fakeXrayHost = serve({
    fetch: (req) => {
      const url = new URL(req.url);
      if (url.pathname === "/xray/api/v1/system/version")
        return createJSONResponse({
          xray_version: "3.80.0",
          xray_revision: "abc123",
        });
      if (url.pathname === "/xray/api/v1/artifacts")
        return createJSONResponse({
          data: [],
          offset: -1,
        });
      return createJSONResponse({});
    },
    port: 0,
  });

  const fakeXrayUrl = `http://${fakeXrayHost.hostname}:${fakeXrayHost.port}`;

  testRequiredVariables(import.meta.dir, {
    resource_id: "test-resource-id",
    xray_url: fakeXrayUrl,
    xray_token: "test-token",
    image: "docker-local/test/image:latest",
  });

  it("creates metadata with vulnerability counts", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      resource_id: "test-resource-id",
      xray_url: fakeXrayUrl,
      xray_token: "test-token",
      image: "docker-local/codercom/enterprise-base:latest",
    });
    const metadata = findResourceInstance(state, "coder_metadata");
    expect(metadata.resource_id).toBe("test-resource-id");
    expect(metadata.icon).toBe("../../../../.icons/jfrog.svg");

    const items = metadata.item as Array<{ key: string; value: string }>;
    const keys = items.map((i) => i.key);
    expect(keys).toContain("Image");
    expect(keys).toContain("Total Vulnerabilities");
    expect(keys).toContain("Critical");
    expect(keys).toContain("High");
    expect(keys).toContain("Medium");
    expect(keys).toContain("Low");

    const imageItem = items.find((i) => i.key === "Image");
    expect(imageItem?.value).toBe(
      "docker-local/codercom/enterprise-base:latest",
    );
  });

  it("allows custom repo and repo_path override", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      resource_id: "test-resource-id",
      xray_url: fakeXrayUrl,
      xray_token: "test-token",
      image: "docker-local/codercom/enterprise-base:latest",
      repo: "custom-repo",
      repo_path: "/custom/path:v1.0",
    });
    const metadata = findResourceInstance(state, "coder_metadata");
    expect(metadata.resource_id).toBe("test-resource-id");
  });
});
