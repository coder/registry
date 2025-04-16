import { describe } from "bun:test";
import { runTerraformInit, testRequiredVariables } from "~test";

describe("nodejs", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  // More tests depend on shebang refactors
});
