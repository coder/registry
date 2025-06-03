import { describe, it, expect } from "bun:test";
import {
  runTerraformApply,
  runTerraformInit,
  findResourceInstance,
} from "~test";

describe("aider", async () => {
  await runTerraformInit(import.meta.dir);

  it("installs aider with default settings", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });

    const instance = findResourceInstance(state, "coder_script");
    expect(instance.script).toContain("Installing Aider");
    expect(instance.script).toContain("curl -LsSf https://aider.chat/install.sh");
    expect(instance.script).toContain("Starting persistent Aider session");
  });

  it("configures tmux when use_tmux is true", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      use_tmux: true,
      use_screen: false,
    });

    const instance = findResourceInstance(state, "coder_script");
    expect(instance.script).toContain("Installing tmux for persistent sessions");
    expect(instance.script).toContain("tmux new-session");
    expect(instance.script).toContain("set -g mouse on");
  });

  it("configures screen when use_screen is true", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      use_screen: true,
      use_tmux: false,
    });

    const instance = findResourceInstance(state, "coder_script");
    expect(instance.script).toContain("Installing screen for persistent sessions");
    expect(instance.script).toContain("screen -U -dmS");
    expect(instance.script).toContain("multiuser on");
  });

  it("runs pre and post install scripts when provided", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      experiment_pre_install_script: "echo 'pre-install'",
      experiment_post_install_script: "echo 'post-install'",
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
    // API key should no longer be exported inline - it's set via coder_env
    expect(instance.script).not.toContain('export ANTHROPIC_API_KEY=');
    expect(instance.script).toContain("--model sonnet");
    expect(instance.script).toContain(
      "Starting Aider using anthropic provider and model: sonnet",
    );

    // Check that coder_env resource is created
    const envInstance = findResourceInstance(state, "coder_env");
    expect(envInstance.name).toBe("ANTHROPIC_API_KEY");
    expect(envInstance.value).toBe("test-anthropic-key");
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
    // API key should no longer be exported inline - it's set via coder_env
    expect(instance.script).not.toContain('export MY_CUSTOM_API_KEY=');
    expect(instance.script).toContain("--model custom-model");
    expect(instance.script).toContain(
      "Starting Aider using custom provider and model: custom-model",
    );

    // Check that coder_env resource is created with custom env var name
    const envInstance = findResourceInstance(state, "coder_env");
    expect(envInstance.name).toBe("MY_CUSTOM_API_KEY");
    expect(envInstance.value).toBe("test-custom-key");
  });
});
