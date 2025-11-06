import { describe, expect, it } from "bun:test";
import {
  executeScriptInContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("cmux", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("runs with default", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });

    const output = await executeScriptInContainer(
      state,
      "alpine/curl",
      "sh",
      "apk add bash tar gzip",
    );

    expect(output.exitCode).toBe(0);
    const expectedLines = [
      "📥 npm not found; downloading tarball from npm registry...",
      "🥳 cmux has been installed in /tmp/cmux",
      "🚀 Starting cmux server on port 4000...",
      "Check logs at /tmp/cmux.log!",
    ];
    for (const line of expectedLines) {
      expect(output.stdout).toContain(line);
    }
  }, 15000);

  it("runs with npm present", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });

    const output = await executeScriptInContainer(
      state,
      "node:20-alpine",
      "sh",
      "apk add bash",
    );

    expect(output.exitCode).toBe(0);
    const expectedLines = [
      "📦 Installing @coder/cmux via npm into /tmp/cmux...",
      "🥳 cmux has been installed in /tmp/cmux",
      "🚀 Starting cmux server on port 4000...",
      "Check logs at /tmp/cmux.log!",
    ];
    for (const line of expectedLines) {
      expect(output.stdout).toContain(line);
    }
  }, 60000);
});
