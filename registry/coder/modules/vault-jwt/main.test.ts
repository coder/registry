import { describe } from "bun:test";
import { runTerraformInit, testRequiredVariables } from "~test";

describe("vault-jwt", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
    vault_addr: "foo",
    vault_jwt_role: "foo",
  });
});
