import { it, expect, describe } from "bun:test";
import {
  runTerraformInit,
  testRequiredVariables,
  runTerraformApply,
} from "../test";

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
      "jetbrains-gateway://connect#type=coder&workspace=default&owner=default&folder=/home/coder&url=https://mydeployment.coder.com&token=$SESSION_TOKEN&ide_product_code=IU&ide_build_number=243.21565.193&ide_download_link=https://download.jetbrains.com/idea/ideaIU-2024.3.tar.gz",
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
});
