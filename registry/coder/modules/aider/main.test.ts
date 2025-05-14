import { describe, expect, it } from "bun:test";
import {
  findResourceInstance,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("aider", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("configures task prompt correctly", async () => {
    const testPrompt = "Add a hello world function";
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });

    const instance = findResourceInstance(state, "coder_script");
    expect(instance.script).toContain(
      'if [ -n "$CODER_MCP_AIDER_TASK_PROMPT" ]',
    );
    expect(instance.script).toContain(
      "aider --architect --yes-always --read CONVENTIONS.md --message",
    );
  });

  it("handles pre and post install scripts", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      experiment_pre_install_script: "echo 'Pre-install script executed'",
      experiment_post_install_script: "echo 'Post-install script executed'",
    });

    const instance = findResourceInstance(state, "coder_script");

    expect(instance.script).toContain("Running pre-install script");
    expect(instance.script).toContain("Running post-install script");
    expect(instance.script).toContain("base64 -d > /tmp/pre_install.sh");
    expect(instance.script).toContain("base64 -d > /tmp/post_install.sh");
  });

  it("validates that use_screen and use_tmux cannot both be true", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      use_screen: true,
      use_tmux: true,
    });

    const instance = findResourceInstance(state, "coder_script");

    expect(instance.script).toContain(
      "Error: Both use_screen and use_tmux cannot be enabled at the same time",
    );
    expect(instance.script).toContain("exit 1");
  });
});
