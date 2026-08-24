import { describe } from "bun:test";
import { runTerraformInit, testRequiredVariables } from "~test";

describe("python", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });
});
