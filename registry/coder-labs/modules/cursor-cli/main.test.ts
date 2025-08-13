import { afterEach, beforeAll, describe, expect, setDefaultTimeout, test } from "bun:test";
import { execContainer, runTerraformInit, writeFileContainer } from "~test";
import { execModuleScript } from "../../../coder/modules/agentapi/test-util";
import { setupContainer, writeExecutable } from "../../../coder/modules/agentapi/test-util";

let cleanupFns: (() => Promise<void>)[] = [];
const registerCleanup = (fn: () => Promise<void>) => cleanupFns.push(fn);

afterEach(async () => {
  const fns = cleanupFns.slice().reverse();
  cleanupFns = [];
  for (const fn of fns) {
    try {
      await fn();
    } catch (err) {
      console.error(err);
    }
  }
});

const setup = async (vars?: Record<string, string>) => {
  const projectDir = "/home/coder/project";
  const { id, coderScript, cleanup } = await setupContainer({
    moduleDir: import.meta.dir,
    image: "codercom/enterprise-minimal:latest",
    vars: {
      folder: projectDir,
      install_cursor_cli: "false",
      ...vars,
    },
  });
  registerCleanup(cleanup);
  // Ensure project dir exists
  await execContainer(id, ["bash", "-c", `mkdir -p '${projectDir}'`]);
  // Write the module's script to the container
  await writeExecutable({
    containerId: id,
    filePath: "/home/coder/script.sh",
    content: coderScript.script,
  });
  return { id, projectDir };
};

setDefaultTimeout(180 * 1000);

describe("cursor-cli", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("installs Cursor via official installer and runs --help", async () => {
    const { id } = await setup({ install_cursor_cli: "true", ai_prompt: "--help" });
    const resp = await execModuleScript(id);
    expect(resp.exitCode).toBe(0);

    // Verify the start log captured the invocation
    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/script.log",
    ]);
    expect(startLog.exitCode).toBe(0);
    expect(startLog.stdout).toContain("cursor-agent");
  });

  test("model and force flags propagate", async () => {
    const { id } = await setup({ model: "sonnet-4", force: "true", ai_prompt: "status" });
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/cursor-agent",
      content: `#!/bin/sh\necho cursor-agent invoked\nfor a in "$@"; do echo arg:$a; done\nexit 0\n`,
    });

    const resp = await execModuleScript(id);
    expect(resp.exitCode).toBe(0);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/script.log",
    ]);
    expect(startLog.exitCode).toBe(0);
    expect(startLog.stdout).toContain("-m sonnet-4");
    expect(startLog.stdout).toContain("-f");
    expect(startLog.stdout).toContain("status");
  });

  test("writes workspace mcp.json when provided", async () => {
    const mcp = JSON.stringify({ mcpServers: { foo: { command: "foo", type: "stdio" } } });
    const { id } = await setup({ mcp_json: mcp });
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/cursor-agent",
      content: `#!/bin/sh\necho ok\n`,
    });
    const resp = await execModuleScript(id);
    expect(resp.exitCode).toBe(0);

    const mcpContent = await execContainer(id, [
      "bash",
      "-c",
      `cat '/home/coder/project/.cursor/mcp.json'`,
    ]);
    expect(mcpContent.exitCode).toBe(0);
    expect(mcpContent.stdout).toContain("mcpServers");
    expect(mcpContent.stdout).toContain("foo");
  });

  test("fails when cursor-agent missing", async () => {
    const { id } = await setup();
    const resp = await execModuleScript(id);
    expect(resp.exitCode).not.toBe(0);
    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/script.log || true",
    ]);
    expect(startLog.stdout).toContain("cursor-agent not found");
  });

  test("install step logs folder", async () => {
    const { id } = await setup({ install_cursor_cli: "false" });
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/cursor-agent",
      content: `#!/bin/sh\necho ok\n`,
    });
    const resp = await execModuleScript(id);
    expect(resp.exitCode).toBe(0);
    const installLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/script.log",
    ]);
    expect(installLog.exitCode).toBe(0);
    expect(installLog.stdout).toContain("folder: /home/coder/project");
  });
});


