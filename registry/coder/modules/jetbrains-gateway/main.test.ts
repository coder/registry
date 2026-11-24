import { it, expect, describe, afterAll } from "bun:test";
import {
  runTerraformInit,
  testRequiredVariables,
  runTerraformApply,
} from "~test";

describe("jetbrains-gateway", async () => {
  await runTerraformInit(import.meta.dir);

  await testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
    folder: "/home/foo",
  });

  it("should create a link with the default values", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      // These are all required.
      agent_id: "foo",
      folder: "/home/coder",
    });
    expect(state.outputs.url.value).toBe(
      "jetbrains-gateway://connect#type=coder&workspace=default&owner=default&folder=/home/coder&url=https://mydeployment.coder.com&token=$SESSION_TOKEN&ide_product_code=IU&ide_build_number=243.21565.193&ide_download_link=https://download.jetbrains.com/idea/ideaIU-2024.3.tar.gz&agent=",
    );

    const coder_app = state.resources.find(
      (res) => res.type === "coder_app" && res.name === "gateway",
    );

    expect(coder_app).not.toBeNull();
    expect(coder_app?.instances.length).toBe(1);
    expect(coder_app?.instances[0].attributes.order).toBeNull();
  });

  it("default to first ide", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      folder: "/home/foo",
      jetbrains_ides: '["IU", "GO", "PY"]',
    });
    expect(state.outputs.identifier.value).toBe("IU");
  });

  it("optionally includes agent when an agent name is provided", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      agent_name: "main",
      folder: "/home/coder",
    });

    expect(state.outputs.url.value).toBe(
      "jetbrains-gateway://connect#type=coder&workspace=default&owner=default&folder=/home/coder&url=https://mydeployment.coder.com&token=$SESSION_TOKEN&ide_product_code=IU&ide_build_number=243.21565.193&ide_download_link=https://download.jetbrains.com/idea/ideaIU-2024.3.tar.gz&agent=main",
    );
  });

  it("includes the agent parameter even when the provided value is blank", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      agent_name: "  ",
      folder: "/home/coder",
    });

    expect(state.outputs.url.value).toBe(
      "jetbrains-gateway://connect#type=coder&workspace=default&owner=default&folder=/home/coder&url=https://mydeployment.coder.com&token=$SESSION_TOKEN&ide_product_code=IU&ide_build_number=243.21565.193&ide_download_link=https://download.jetbrains.com/idea/ideaIU-2024.3.tar.gz&agent=  ",
    );
  });

  describe("products_json_url", () => {
    const release = (
      code: string,
      file: string,
      build: string,
      extra: Record<string, unknown> = {},
    ) => ({
      code,
      alternativeCodes: [code],
      releases: [
        {
          type: "release",
          downloads: {
            linux: { link: file },
            linuxARM64: { link: file.replace(".tar.gz", "-aarch64.tar.gz") },
          },
          version: "2026.1",
          majorVersion: "2026.1",
          build,
        },
      ],
      ...extra,
    });

    // Layout produced by jetbrains-clients-downloader: links in the root
    // products.json are relative to backends/, links in per-IDE files are
    // relative to backends/<CODE>/.
    const files: Record<string, unknown> = {
      "/mirror/backends/products.json": [
        release("PY", "PY/pycharm-2026.1.tar.gz", "261.22158.340", {
          alternativeCodes: ["PYA", "PY"],
        }),
        release("GO", "GO/goland-2026.1.tar.gz", "261.22158.291"),
        release("IU", "https://cdn.example.com/ideaIU-2026.1.tar.gz", "261.1"),
      ],
      "/mirror/backends/PY/products.json": [
        release("PY", "pycharm-2026.1.tar.gz", "261.22158.340"),
      ],
    };

    const server = Bun.serve({
      port: 0,
      fetch(req) {
        const body = files[new URL(req.url).pathname];
        return body
          ? Response.json(body)
          : new Response("not found", { status: 404 });
      },
    });
    const base = `http://localhost:${server.port}/mirror/backends`;

    afterAll(() => server.stop(true));

    it("resolves build and relative link from the root products.json", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        jetbrains_ides: '["PY", "GO"]',
        products_json_url: `${base}/products.json`,
      });
      expect(state.outputs.build_number.value).toBe("261.22158.340");
      expect(state.outputs.version.value).toBe("2026.1");
      expect(state.outputs.download_link.value).toBe(
        `${base}/PY/pycharm-2026.1.tar.gz`,
      );
      expect(state.outputs.url.value).toContain(
        `&ide_build_number=261.22158.340&ide_download_link=${base}/PY/pycharm-2026.1.tar.gz&`,
      );
    });

    it("resolves links from a per-IDE products.json via {code}", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        jetbrains_ides: '["PY"]',
        products_json_url: `${base}/{code}/products.json`,
      });
      expect(state.outputs.download_link.value).toBe(
        `${base}/PY/pycharm-2026.1.tar.gz`,
      );
    });

    it("uses the arm64 download and keeps absolute links", async () => {
      const arm = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        jetbrains_ides: '["GO"]',
        arch: "arm64",
        products_json_url: `${base}/products.json`,
      });
      expect(arm.outputs.download_link.value).toBe(
        `${base}/GO/goland-2026.1-aarch64.tar.gz`,
      );

      const absolute = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        jetbrains_ides: '["IU"]',
        products_json_url: `${base}/products.json`,
      });
      expect(absolute.outputs.download_link.value).toBe(
        "https://cdn.example.com/ideaIU-2026.1.tar.gz",
      );
    });

    it("takes precedence over latest without calling the releases API", async () => {
      const state = await runTerraformApply(import.meta.dir, {
        agent_id: "foo",
        folder: "/home/coder",
        jetbrains_ides: '["PY"]',
        latest: true,
        releases_base_link: "http://127.0.0.1:1",
        products_json_url: `${base}/products.json`,
      });
      expect(state.outputs.build_number.value).toBe("261.22158.340");
    });

    it("fails when the IDE is missing from products.json", async () => {
      await expect(
        runTerraformApply(import.meta.dir, {
          agent_id: "foo",
          folder: "/home/coder",
          jetbrains_ides: '["WS"]',
          products_json_url: `${base}/products.json`,
        }),
      ).rejects.toThrow(
        /WS has no release channel entry with a linux download/,
      );
    });
  });
});
