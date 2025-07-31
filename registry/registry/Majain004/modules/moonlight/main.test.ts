import { test, expect } from "@coder/registry-test";
import * as tf from "@cdktf/provider-terraform";

// Test Moonlight module for Windows with GameStream
test("moonlight module creates coder_app and coder_script for Windows GameStream", async ({ terraform }) => {
  const stack = terraform.stack({
    agent_id: "test-agent",
    os: "windows",
    streaming_method: "gamestream",
    port: 47984,
    quality: "high",
  });
  expect(stack).toHaveResource("coder_app.moonlight");
  expect(stack).toHaveResource("coder_script.moonlight_setup");
});

// Test Moonlight module for Linux with Sunshine
test("moonlight module creates coder_app and coder_script for Linux Sunshine", async ({ terraform }) => {
  const stack = terraform.stack({
    agent_id: "test-agent",
    os: "linux",
    streaming_method: "sunshine",
    port: 47984,
    quality: "high",
  });
  expect(stack).toHaveResource("coder_app.moonlight");
  expect(stack).toHaveResource("coder_script.moonlight_setup");
});

// Test Moonlight module with auto detection
test("moonlight module works with auto streaming method", async ({ terraform }) => {
  const stack = terraform.stack({
    agent_id: "test-agent",
    os: "windows",
    streaming_method: "auto",
    port: 47984,
    quality: "high",
  });
  expect(stack).toHaveResource("coder_script.moonlight_setup");
});

// Test with custom port
test("moonlight module works with custom port", async ({ terraform }) => {
  const stack = terraform.stack({
    agent_id: "test-agent",
    os: "linux",
    port: 48000,
    quality: "ultra",
  });
  expect(stack).toHaveResource("coder_script.moonlight_setup");
});

// Test with different quality settings
test("moonlight module works with different quality settings", async ({ terraform }) => {
  const qualities = ["low", "medium", "high", "ultra"];
  
  for (const quality of qualities) {
    const stack = terraform.stack({
      agent_id: "test-agent",
      os: "windows",
      quality: quality,
    });
    expect(stack).toHaveResource("coder_script.moonlight_setup");
  }
});

// Test with subdomain disabled
test("moonlight module works with subdomain disabled", async ({ terraform }) => {
  const stack = terraform.stack({
    agent_id: "test-agent",
    os: "linux",
    subdomain: false,
  });
  expect(stack).toHaveResource("coder_app.moonlight");
});

// Test GPU detection scenarios
test("moonlight module handles different GPU scenarios", async ({ terraform }) => {
  // Test with GameStream method
  const gamestreamStack = terraform.stack({
    agent_id: "test-agent",
    os: "windows",
    streaming_method: "gamestream",
  });
  expect(gamestreamStack).toHaveResource("coder_script.moonlight_setup");
  
  // Test with Sunshine method
  const sunshineStack = terraform.stack({
    agent_id: "test-agent",
    os: "linux",
    streaming_method: "sunshine",
  });
  expect(sunshineStack).toHaveResource("coder_script.moonlight_setup");
}); 