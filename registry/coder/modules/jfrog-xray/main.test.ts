import { serve } from "bun";
import { describe, expect, it } from "bun:test";
import {
  createJSONResponse,
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
    xray_url: fakeXrayUrl,
    xray_token: "test-token",
    image: "docker-local/test/image:latest",
  });

  it("outputs vulnerability counts", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      xray_url: fakeXrayUrl,
      xray_token: "test-token",
      image: "docker-local/codercom/enterprise-base:latest",
    });
    const outputs = state.values?.outputs;
    expect(outputs).toBeDefined();
    expect(outputs?.critical).toBeDefined();
    expect(outputs?.high).toBeDefined();
    expect(outputs?.medium).toBeDefined();
    expect(outputs?.low).toBeDefined();
    expect(outputs?.total).toBeDefined();
  });

  it("allows custom repo and repo_path override", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      xray_url: fakeXrayUrl,
      xray_token: "test-token",
      image: "docker-local/codercom/enterprise-base:latest",
      repo: "custom-repo",
      repo_path: "/custom/path:v1.0",
    });
    const outputs = state.values?.outputs;
    expect(outputs).toBeDefined();
  });
});
