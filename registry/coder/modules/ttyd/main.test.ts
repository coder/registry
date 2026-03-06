import { describe, expect, it } from "bun:test";
import {
  executeScriptInContainer,
  runTerraformApply,
  runTerraformInit,
  type scriptOutput,
  testRequiredVariables,
} from "~test";

function testBaseLine(output: scriptOutput) {
  expect(output.exitCode).toBe(0);

  const expectedLines = [
    "Installing ttyd",
    "Installation complete!",
    "Starting ttyd in background...",
  ];

  for (const line of expectedLines) {
    expect(output.stdout).toContain(line);
  }
}

describe("ttyd", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("fails with empty command", async () => {
    await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      command: "[]",
    }).catch((e) => {
      if (!e.message.startsWith("\nError: Invalid value for variable")) {
        throw e;
      }
    });
  });

  it("runs with default", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });

    const output = await executeScriptInContainer(
      state,
      "alpine/curl",
      "sh",
      "apk add bash",
    );

    testBaseLine(output);
  }, 30000);

  it("runs with custom command", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      command: '["htop"]',
    });

    const output = await executeScriptInContainer(
      state,
      "alpine/curl",
      "sh",
      "apk add bash",
    );

    testBaseLine(output);
    expect(output.stdout).toContain("htop");
  }, 30000);

  it("runs with writable=false", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      writable: "false",
    });

    const output = await executeScriptInContainer(
      state,
      "alpine/curl",
      "sh",
      "apk add bash",
    );

    testBaseLine(output);
  }, 30000);

  it("runs with subdomain=false", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      agent_name: "main",
      subdomain: "false",
    });

    const output = await executeScriptInContainer(
      state,
      "alpine/curl",
      "sh",
      "apk add bash",
    );

    testBaseLine(output);
  }, 30000);

  it("runs with additional_args", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      additional_args: "-t fontSize=18",
    });

    const output = await executeScriptInContainer(
      state,
      "alpine/curl",
      "sh",
      "apk add bash",
    );

    testBaseLine(output);
    expect(output.stdout).toContain("fontSize=18");
  }, 30000);
});
