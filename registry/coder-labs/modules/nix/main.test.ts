import { describe, expect, it } from "bun:test";
import path from "node:path";
import { runTerraformInit, testRequiredVariables } from "~test";

describe("nix", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    flake_ref: "https://example.org/flake",
    flake_attr: "host",
  });

  it("lifecycle library passes its shell tests", async () => {
    const proc = Bun.spawn(
      ["bash", path.join(import.meta.dir, "scripts", "lifecycle.test.sh")],
      { stdout: "pipe", stderr: "pipe" },
    );
    const [exitCode, stdout, stderr] = await Promise.all([
      proc.exited,
      new Response(proc.stdout).text(),
      new Response(proc.stderr).text(),
    ]);
    if (exitCode !== 0) {
      console.error(stdout, stderr);
    }
    expect(exitCode).toBe(0);
    expect(stdout).toContain("lifecycle tests passed");
  });
});
