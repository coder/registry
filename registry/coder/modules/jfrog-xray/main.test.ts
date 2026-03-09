import { serve } from "bun";
import { describe, expect, it } from "bun:test";
import { createJSONResponse, runTerraformInit, runTerraformApply } from "~test";

describe("jfrog-xray", async () => {
  await runTerraformInit(import.meta.dir);

  // Mock server simulating a local repo with direct scan results
  const mockLocalRepo = serve({
    fetch: (req) => {
      const url = new URL(req.url);
      if (url.pathname === "/xray/api/v1/system/version")
        return createJSONResponse({
          xray_version: "3.80.0",
          xray_revision: "abc123",
        });
      if (url.pathname === "/xray/api/v1/artifacts")
        return createJSONResponse({
          data: [
            {
              name: "myapp/backend/v1.0.0",
              repo_path: "/myapp/backend/v1.0.0/manifest.json",
              size: "50.00 MB",
              sec_issues: {
                critical: 1,
                high: 3,
                medium: 5,
                low: 10,
                total: 19,
              },
              scans_status: {
                overall: {
                  status: "DONE",
                  time: "2026-03-04T22:00:02Z",
                },
              },
              violations: 0,
            },
          ],
          offset: 0,
        });
      return createJSONResponse({});
    },
    port: 0,
  });

  // Mock server simulating a remote repo with cache behavior
  // Returns both tag manifest (0 vulns, 0 size) and SHA manifest (real vulns, real size)
  const mockRemoteRepo = serve({
    fetch: (req) => {
      const url = new URL(req.url);
      if (url.pathname === "/xray/api/v1/system/version")
        return createJSONResponse({
          xray_version: "3.80.0",
          xray_revision: "abc123",
        });
      if (url.pathname === "/xray/api/v1/artifacts")
        return createJSONResponse({
          data: [
            {
              name: "codercom/enterprise-base/ubuntu",
              repo_path: "/codercom/enterprise-base/ubuntu/list.manifest.json",
              size: "0.00 B",
              sec_issues: { total: 0 },
              scans_status: {
                overall: { status: "DONE" },
              },
              violations: 0,
            },
            {
              name: "codercom/enterprise-base/sha256__abc123def456",
              repo_path:
                "/codercom/enterprise-base/sha256__abc123def456/manifest.json",
              size: "359.33 MB",
              sec_issues: {
                critical: 2,
                high: 6,
                medium: 20,
                low: 23,
                total: 51,
              },
              scans_status: {
                overall: { status: "DONE" },
              },
              violations: 2,
            },
          ],
          offset: 0,
        });
      return createJSONResponse({});
    },
    port: 0,
  });

  // Mock server returning empty results (image not scanned)
  const mockEmptyResults = serve({
    fetch: (req) => {
      const url = new URL(req.url);
      if (url.pathname === "/xray/api/v1/system/version")
        return createJSONResponse({
          xray_version: "3.80.0",
          xray_revision: "abc123",
        });
      if (url.pathname === "/xray/api/v1/artifacts")
        return createJSONResponse({ data: [], offset: -1 });
      return createJSONResponse({});
    },
    port: 0,
  });

  const localRepoUrl = `http://${mockLocalRepo.hostname}:${mockLocalRepo.port}`;
  const remoteRepoUrl = `http://${mockRemoteRepo.hostname}:${mockRemoteRepo.port}`;
  const emptyResultsUrl = `http://${mockEmptyResults.hostname}:${mockEmptyResults.port}`;

  const getProviderEnv = (url: string) => ({
    XRAY_URL: url,
    XRAY_ACCESS_TOKEN: "test-token",
  });

  it("validates required variable: xray_url", async () => {
    try {
      await runTerraformApply(
        import.meta.dir,
        {
          xray_token: "test-token",
          image: "docker-local/test/image:latest",
        },
        getProviderEnv(localRepoUrl),
      );
      throw new Error("Expected apply to fail without xray_url");
    } catch (ex) {
      if (!(ex instanceof Error)) throw new Error("Unknown error");
      expect(ex.message).toContain('input variable "xray_url" is not set');
    }
  });

  it("validates required variable: xray_token", async () => {
    try {
      await runTerraformApply(
        import.meta.dir,
        {
          xray_url: localRepoUrl,
          image: "docker-local/test/image:latest",
        },
        getProviderEnv(localRepoUrl),
      );
      throw new Error("Expected apply to fail without xray_token");
    } catch (ex) {
      if (!(ex instanceof Error)) throw new Error("Unknown error");
      expect(ex.message).toContain('input variable "xray_token" is not set');
    }
  });

  it("validates required variable: image", async () => {
    try {
      await runTerraformApply(
        import.meta.dir,
        {
          xray_url: localRepoUrl,
          xray_token: "test-token",
        },
        getProviderEnv(localRepoUrl),
      );
      throw new Error("Expected apply to fail without image");
    } catch (ex) {
      if (!(ex instanceof Error)) throw new Error("Unknown error");
      expect(ex.message).toContain('input variable "image" is not set');
    }
  });

  it("returns vulnerability counts for local repository", async () => {
    const state = await runTerraformApply(
      import.meta.dir,
      {
        xray_url: localRepoUrl,
        xray_token: "test-token",
        image: "docker-local/myapp/backend:v1.0.0",
      },
      getProviderEnv(localRepoUrl),
    );

    expect(state.outputs.critical.value).toBe(1);
    expect(state.outputs.high.value).toBe(3);
    expect(state.outputs.medium.value).toBe(5);
    expect(state.outputs.low.value).toBe(10);
    expect(state.outputs.total.value).toBe(19);
  });

  it("returns zero counts when image has no scan results", async () => {
    const state = await runTerraformApply(
      import.meta.dir,
      {
        xray_url: emptyResultsUrl,
        xray_token: "test-token",
        image: "docker-local/unscanned/image:latest",
      },
      getProviderEnv(emptyResultsUrl),
    );

    expect(state.outputs.critical.value).toBe(0);
    expect(state.outputs.high.value).toBe(0);
    expect(state.outputs.medium.value).toBe(0);
    expect(state.outputs.low.value).toBe(0);
    expect(state.outputs.total.value).toBe(0);
  });

  it("uses cache repo when use_cache_repo is enabled", async () => {
    const state = await runTerraformApply(
      import.meta.dir,
      {
        xray_url: remoteRepoUrl,
        xray_token: "test-token",
        image: "docker-remote/codercom/enterprise-base:ubuntu",
        use_cache_repo: true,
      },
      getProviderEnv(remoteRepoUrl),
    );

    // Should find the SHA artifact with actual vulnerabilities
    expect(state.outputs.critical.value).toBe(2);
    expect(state.outputs.high.value).toBe(6);
    expect(state.outputs.medium.value).toBe(20);
    expect(state.outputs.low.value).toBe(23);
    expect(state.outputs.total.value).toBe(51);
    expect(state.outputs.violations.value).toBe(2);
    expect(state.outputs.artifact_name.value).toContain("sha256__");
  });

  it("allows custom repo and repo_path override", async () => {
    const state = await runTerraformApply(
      import.meta.dir,
      {
        xray_url: localRepoUrl,
        xray_token: "test-token",
        image: "ignored/path:tag",
        repo: "docker-local",
        repo_path: "/myapp/backend/v1.0.0",
      },
      getProviderEnv(localRepoUrl),
    );

    expect(state.outputs.total.value).toBe(19);
  });
});
