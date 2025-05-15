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
      task_prompt: testPrompt,
    });

    const instance = findResourceInstance(state, "coder_script");
    expect(instance.script).toContain(
      `This is your current task: ${testPrompt}`,
    );
    expect(instance.script).toContain("aider --architect --yes-always");
  });

  it("handles custom system prompt", async () => {
    const customPrompt = "Report all tasks with state: working";
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      system_prompt: customPrompt,
    });

    const instance = findResourceInstance(state, "coder_script");
    expect(instance.script).toContain(customPrompt);
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

  it("configures Aider with known provider and model", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      ai_provider: "anthropic",
      ai_model: "sonnet",
      ai_api_key: "test-anthropic-key",
    });

    const instance = findResourceInstance(state, "coder_script");
    expect(instance.script).toContain(
      'export ANTHROPIC_API_KEY=\\"test-anthropic-key\\"',
    );
    expect(instance.script).toContain("--model sonnet");
    expect(instance.script).toContain(
      "Starting Aider using anthropic provider and model: sonnet",
    );
  });

  it("handles custom provider with custom env var and API key", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      ai_provider: "custom",
      custom_env_var_name: "MY_CUSTOM_API_KEY",
      ai_model: "custom-model",
      ai_api_key: "test-custom-key",
    });

    const instance = findResourceInstance(state, "coder_script");
    expect(instance.script).toContain(
      'export MY_CUSTOM_API_KEY=\\"test-custom-key\\"',
    );
    expect(instance.script).toContain("--model custom-model");
    expect(instance.script).toContain(
      "Starting Aider using custom provider and model: custom-model",
    );
  });
});
