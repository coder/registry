import { describe, expect, it } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("coder-utils", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "test-agent-id",
    module_directory: "$HOME/.coder-modules/test/example",
    install_script: "echo 'install'",
  });

  it("rejects invalid module_directory", async () => {
    try {
      await runTerraformApply(import.meta.dir, {
        agent_id: "test-agent-id",
        module_directory: "$HOME/.coder-modules/test",
        install_script: "echo 'install'",
      });
    } catch (ex) {
      if (!(ex instanceof Error)) {
        throw new Error("Unknown error generated");
      }

      expect(ex.message).toContain("module_directory must match the pattern");
      expect(ex.message).toContain(
        "'$HOME/.coder-modules/<namespace>/<module-name>'",
      );
      return;
    }

    throw new Error("module_directory validation should have failed");
  });
});
