import { describe } from "bun:test";
import { runTerraformInit, testRequiredVariables } from "~test";

describe("agent-helper", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "test-agent-id",
    agent_name: "test-agent",
    module_dir_name: ".test-module",
    start_script: "echo 'start'",
  });
});
