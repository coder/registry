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

  const stdout = output.stdout.join("\n");
  expect(stdout).toContain("Installing ttyd");
  expect(stdout).toContain("Installation complete!");
  expect(stdout).toContain("Starting ttyd in background...");
}

describe("ttyd", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
    command: "bash",
  });

  it("runs with bash", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      command: "bash",
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
      command: "htop",
    });

    const output = await executeScriptInContainer(
      state,
      "alpine/curl",
      "sh",
      "apk add bash",
    );

    testBaseLine(output);
    expect(output.stdout.join("\n")).toContain("htop");
  }, 30000);

  it("runs with writable=false", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      command: "bash",
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
      command: "bash",
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
      command: "bash",
      additional_args: "-t fontSize=18",
    });

    const output = await executeScriptInContainer(
      state,
      "alpine/curl",
      "sh",
      "apk add bash",
    );

    testBaseLine(output);
    expect(output.stdout.join("\n")).toContain("fontSize=18");
  }, 30000);
});
