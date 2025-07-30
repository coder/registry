import { test, expect } from "@coder/registry-test";
import * as tf from "@cdktf/provider-terraform";

// Basic test for Parsec module

test("parsec module creates coder_app and coder_script for Windows", async ({ terraform }) => {
  const stack = terraform.stack({
    agent_id: "test-agent",
    os: "windows",
    port: 8000,
  });
  expect(stack).toHaveResource("coder_app.parsec");
  expect(stack).toHaveResource("coder_script.parsec_install");
});

test("parsec module creates coder_app and coder_script for Linux", async ({ terraform }) => {
  const stack = terraform.stack({
    agent_id: "test-agent",
    os: "linux",
    port: 8000,
  });
  expect(stack).toHaveResource("coder_app.parsec");
  expect(stack).toHaveResource("coder_script.parsec_install");
});