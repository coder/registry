import { describe, expect, it } from "bun:test";
import { runTerraformInit, testRequiredVariables, runTerraformApply } from "~test";

describe("nodejs", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("accepts pre_install_script and post_install_script", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      pre_install_script: "echo pre",
      post_install_script: "echo post",
    });
    expect(state).toBeDefined();
  });

  it("works without pre/post install scripts", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    expect(state).toBeDefined();
  });
});
