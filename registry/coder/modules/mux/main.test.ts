import { describe, expect, it } from "bun:test";
import {
  executeScriptInContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

describe("mux", async () => {
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
      "apk add --no-cache bash tar gzip ca-certificates findutils nodejs && update-ca-certificates",
    );
    if (output.exitCode !== 0) {
      console.log("STDOUT:\n" + output.stdout.join("\n"));
      console.log("STDERR:\n" + output.stderr.join("\n"));
    }
    expect(output.exitCode).toBe(0);
    const expectedLines = [
      "📥 npm not found; downloading tarball from npm registry...",
      "🥳 mux has been installed in /tmp/mux",
      "🚀 Starting mux server on port 4000...",
      "Check logs at /tmp/mux.log!",
    ];
    for (const line of expectedLines) {
      expect(output.stdout).toContain(line);
    }
  }, 60000);

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
      "📦 Installing mux via npm into /tmp/mux...",
      "⏭️  Skipping npm lifecycle scripts with --ignore-scripts",
      "🥳 mux has been installed in /tmp/mux",
      "🚀 Starting mux server on port 4000...",
      "Check logs at /tmp/mux.log!",
    ];
    for (const line of expectedLines) {
      expect(output.stdout).toContain(line);
    }
  }, 180000);
});
