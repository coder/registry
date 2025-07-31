import { test, expect } from "@coder/registry-test";
import * as tf from "@cdktf/provider-terraform";

// Test Parsec module for Windows
test("parsec module creates coder_app and coder_script for Windows", async ({ terraform }) => {
  const stack = terraform.stack({
    agent_id: "test-agent",
    os: "windows",
    port: 8000,
  });
  expect(stack).toHaveResource("coder_app.parsec");
  expect(stack).toHaveResource("coder_script.parsec_install");
});

// Test Parsec module for Linux
test("parsec module creates coder_app and coder_script for Linux", async ({ terraform }) => {
  const stack = terraform.stack({
    agent_id: "test-agent",
    os: "linux",
    port: 8000,
  });
  expect(stack).toHaveResource("coder_app.parsec");
  expect(stack).toHaveResource("coder_script.parsec_install");
});

// Test with custom port
test("parsec module works with custom port", async ({ terraform }) => {
  const stack = terraform.stack({
    agent_id: "test-agent",
    os: "windows",
    port: 9000,
  });
  expect(stack).toHaveResource("coder_script.parsec_install");
});

// Test with subdomain disabled
test("parsec module works with subdomain disabled", async ({ terraform }) => {
  const stack = terraform.stack({
    agent_id: "test-agent",
    os: "linux",
    subdomain: false,
  });
  expect(stack).toHaveResource("coder_app.parsec");
}); 