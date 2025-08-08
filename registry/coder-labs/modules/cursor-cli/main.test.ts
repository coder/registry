import { test, afterEach, describe, setDefaultTimeout, beforeAll, expect } from "bun:test";
import { execContainer, readFileContainer, runTerraformInit, runTerraformApply, writeFileContainer, runContainer, removeContainer, findResourceInstance } from "~test";
import dedent from "dedent";

let cleanupFunctions: (() => Promise<void>)[] = [];
const registerCleanup = (cleanup: () => Promise<void>) => {
  cleanupFunctions.push(cleanup);
};

afterEach(async () => {
  const cleanupFnsCopy = cleanupFunctions.slice().reverse();
  cleanupFunctions = [];
  for (const cleanup of cleanupFnsCopy) {
    try {
      await cleanup();
    } catch (error) {
      console.error("Error during cleanup:", error);
    }
  }
});

const writeExecutable = async (containerId: string, filePath: string, content: string) => {
  await writeFileContainer(containerId, filePath, content, { user: "root" });
  await execContainer(containerId, ["bash", "-c", `chmod 755 ${filePath}`], ["--user", "root"]);
};

const loadTestFile = async (...relativePath: string[]) => {
  return await Bun.file(new URL(`./testdata/${relativePath.join("/")}`, import.meta.url)).text();
};

const setup = async (vars?: Record<string, string>): Promise<{ id: string }> => {
  const state = await runTerraformApply(import.meta.dir, {
    agent_id: "foo",
    install_cursor_cli: "false",
    ...vars,
  });
  const coderScript = findResourceInstance(state, "coder_script");
  const id = await runContainer("codercom/enterprise-node:latest");
  registerCleanup(async () => removeContainer(id));
  await writeExecutable(id, "/home/coder/script.sh", coderScript.script);
  await writeExecutable(id, "/usr/bin/cursor", await loadTestFile("cursor-mock.sh"));
  return { id };
};

setDefaultTimeout(60 * 1000);

describe("cursor-cli", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  test("happy-path-interactive", async () => {
    const { id } = await setup();
    const resp = await execContainer(id, ["bash", "-c", "cd /home/coder && ./script.sh"]);
    if (resp.exitCode !== 0) {
      console.log(resp.stdout);
      console.log(resp.stderr);
    }
    expect(resp.exitCode).toBe(0);
    const startLog = await readFileContainer(id, "/home/coder/.cursor-cli-module/start.log");
    expect(startLog).toContain("agent");
    expect(startLog).toContain("--interactive");
  });

  test("non-interactive-with-cmd", async () => {
    const { id } = await setup({ interactive: "false", non_interactive_cmd: "run --once" });
    const resp = await execContainer(id, ["bash", "-c", "cd /home/coder && ./script.sh"]);
    expect(resp.exitCode).toBe(0);
    const startLog = await readFileContainer(id, "/home/coder/.cursor-cli-module/start.log");
    expect(startLog).toContain("run");
    expect(startLog).toContain("--once");
    expect(startLog).not.toContain("--interactive");
  });

  test("model-and-force-and-extra-args", async () => {
    const { id } = await setup({ model: "test-model", force: "true" });
    const resp = await execContainer(id, ["bash", "-c", "cd /home/coder && ./script.sh"], ["--env", "TF_VAR_extra_args=--foo\nbar"]);
    expect(resp.exitCode).toBe(0);
    const startLog = await readFileContainer(id, "/home/coder/.cursor-cli-module/start.log");
    expect(startLog).toContain("--model");
    expect(startLog).toContain("test-model");
    expect(startLog).toContain("--force");
  });

  test("additional-settings-merge", async () => {
    const settings = dedent`
      {"mcpServers": {"coder": {"command": "coder", "args": ["exp","mcp","server"], "type": "stdio"}}}
    `;
    const { id } = await setup({ additional_settings: settings });
    const resp = await execContainer(id, ["bash", "-c", "cd /home/coder && ./script.sh"]);
    expect(resp.exitCode).toBe(0);
    const cfg = await readFileContainer(id, "/home/coder/.cursor/settings.json");
    expect(cfg).toContain("mcpServers");
    expect(cfg).toContain("coder");
  });
});
