import { describe, expect, it, setDefaultTimeout } from "bun:test";
import {
  executeScriptInContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

const createScript = (
  path: string,
  content: string,
  executable = true,
): string => {
  const encodedPath = Buffer.from(path).toString("base64");
  const encodedContent = Buffer.from(content).toString("base64");

  return [
    `script_path="$(printf '%s' '${encodedPath}' | base64 -d)"`,
    'mkdir -p "$(dirname "$script_path")"',
    `printf '%s' '${encodedContent}' | base64 -d > "$script_path"`,
    executable ? 'chmod +x "$script_path"' : "",
  ]
    .filter(Boolean)
    .join("\n");
};

setDefaultTimeout(30 * 1000);

describe("personalize", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("warns without personalize script", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    const output = await executeScriptInContainer(state, "alpine");
    expect(output.exitCode).toBe(0);
    expect(output.stdout).toEqual([
      "✨ \u001b[0;1mYou don't have a personalize script!",
      "",
      "Create a script at \u001b[36;40;1m~/personalize\u001b[0m and make it executable.",
      "It will run every time your workspace starts. Use it to install personal packages!",
    ]);
  });

  it("warns when the personalize script is not executable", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    const output = await executeScriptInContainer(
      state,
      "alpine",
      "sh",
      createScript(
        "/root/personalize",
        "#!/bin/sh\necho should-not-run\n",
        false,
      ),
    );

    expect(output.exitCode).toBe(0);
    expect(output.stdout).toContain(
      "🔐 Your personalize script isn't executable!",
    );
    expect(output.stdout).not.toContain("should-not-run");
  });

  it("runs an executable personalize script", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    const output = await executeScriptInContainer(
      state,
      "alpine",
      "sh",
      createScript(
        "/root/personalize",
        "#!/bin/sh\nprintf 'personalize executed\\n'\n",
      ),
    );

    expect(output.exitCode).toBe(0);
    expect(output.stdout).toEqual(["personalize executed"]);
  });

  it("preserves spaces and shell syntax in a custom path", async () => {
    const path = "/tmp/personalize scripts/$(printf injected) [daily]*";
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      path,
    });
    const output = await executeScriptInContainer(
      state,
      "alpine",
      "sh",
      createScript(path, "#!/bin/sh\nprintf 'custom path executed\\n'\n"),
    );

    expect(output.exitCode).toBe(0);
    expect(output.stdout).toEqual(["custom path executed"]);
  });

  it("preserves the personalize script exit code", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
    });
    const output = await executeScriptInContainer(
      state,
      "alpine",
      "sh",
      createScript("/root/personalize", "#!/bin/sh\nexit 23\n"),
    );

    expect(output.exitCode).toBe(23);
  });
});
