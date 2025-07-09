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
    "\u001b[[0;1mInstalling filebrowser ",
    "🥳 Installation complete! ",
    "👷 Starting filebrowser in background... ",
    "📂 Serving /root at http://localhost:13339 ",
    "📝 Logs at /tmp/filebrowser.log",
  ];

  // we could use expect(output.stdout).toEqual(expect.arrayContaining(expectedLines)), but when it errors, it doesn't say which line is wrong
  for (const line of expectedLines) {
    expect(output.stdout).toContain(line);
  }
}

describe("filebrowser", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("fails with wrong database_path", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      database_path: "nofb",
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
  }, 15000);

  it("runs with database_path var", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      database_path: ".config/filebrowser.db",
    });

    const output = await executeScriptInContainer(
      state,
      "alpine/curl",
      "sh",
      "apk add bash",
    );

    testBaseLine(output);
  }, 15000);

  it("runs with folder var", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      folder: "/home/coder/project",
    });
    const output = await executeScriptInContainer(
      state,
      "alpine/curl",
      "sh",
      "apk add bash",
    );
  }, 15000);

  it("runs with subdomain=false", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      agent_name: "main",
      subdomain: false,
    });

    const output = await executeScriptInContainer(
      state,
      "alpine/curl",
      "sh",
      "apk add bash",
    );

    testBaseLine(output);
  }, 15000);
});
