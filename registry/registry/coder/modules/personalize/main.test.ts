import { describe, expect, it } from "bun:test";
import {
  executeScriptInContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("personalize", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("warns without personalize script", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    const output = await executeScriptInContainer(state, "alpine");
    expect(output.exitCode).toBe(0);
    expect(output.stdout).toEqual([
      "✨ \u001b[0;1mYou don't have a personalize script!",
      "",
      "Run \u001b[36;40;1mtouch ~/personalize && chmod +x ~/personalize\u001b[0m to create one.",
      "It will run every time your workspace starts. Use it to install personal packages!",
    ]);
  });
});
