import { afterEach, beforeAll, describe, expect, setDefaultTimeout, test } from "bun:test";
import { execContainer, runTerraformInit, writeFileContainer } from "~test";
import {
  execModuleScript,
  expectAgentAPIStarted,
  loadTestFile,
  setup as setupUtil
} from "../../../coder/modules/agentapi/test-util";
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

interface SetupProps {
  skipAgentAPIMock?: boolean;
  skipCursorCliMock?: boolean;
  moduleVariables?: Record<string, string>;
  agentapiMockScript?: string;
}

const setup_agentapi_version = async (props?: SetupProps): Promise<{ id: string }> => {
  const projectDir = "/home/coder/project";
  const { id } = await setupUtil({
    moduleDir: import.meta.dir,
    moduleVariables: {
      enable_agentapi: "true",
      install_cursor_cli: props?.skipCursorCliMock ? "true" : "false",
      install_agentapi: props?.skipAgentAPIMock ? "true" : "false",
      folder: projectDir,
      ...props?.moduleVariables,
    },
    registerCleanup,
    projectDir,
    skipAgentAPIMock: props?.skipAgentAPIMock,
    agentapiMockScript: props?.agentapiMockScript,
  });
  if (!props?.skipCursorCliMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/cursor-agent",
      content: await loadTestFile(import.meta.dir, "cursor-cli-mock.sh"),
    });
  }
  return { id };
};

setDefaultTimeout(180 * 1000);

describe("cursor-cli", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  // tests start for the non-agentapi module version

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

  // tests end for the non-agentapi module version

  // tests start for the agentapi module version

  test("agentapi-happy-path", async () => {
    const { id } = await setup_agentapi_version({});
    const resp = await execModuleScript(id);
    expect(resp.exitCode).toBe(0);

    await expectAgentAPIStarted(id);
  });

  test("agentapi-mcp-json", async () => {
    const mcpJson = '{"mcpServers": {"test": {"command": "test-cmd", "type": "stdio"}}}';
    const { id } = await setup_agentapi_version({
      moduleVariables: {
        mcp_json: mcpJson,
      }
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
    expect(mcpContent.stdout).toContain("test");
    expect(mcpContent.stdout).toContain("test-cmd");
    expect(mcpContent.stdout).toContain("/tmp/mcp-hack.sh");
    expect(mcpContent.stdout).toContain("coder");
  });

  test("agentapi-rules-files", async () => {
    const rulesContent = "Always use TypeScript";
    const { id } = await setup_agentapi_version({
      moduleVariables: {
        rules_files: JSON.stringify({ "typescript.md": rulesContent }),
      }
    });
    const resp = await execModuleScript(id);
    expect(resp.exitCode).toBe(0);

    const rulesFile = await execContainer(id, [
      "bash",
      "-c",
      `cat '/home/coder/project/.cursor/rules/typescript.md'`,
    ]);
    expect(rulesFile.exitCode).toBe(0);
    expect(rulesFile.stdout).toContain(rulesContent);
  });

  test("agentapi-api-key", async () => {
    const apiKey = "test-cursor-api-key-123";
    const { id } = await setup_agentapi_version({
      moduleVariables: {
        api_key: apiKey,
      }
    });
    const resp = await execModuleScript(id);
    expect(resp.exitCode).toBe(0);

    const envCheck = await execContainer(id, [
      "bash",
      "-c",
      `env | grep CURSOR_API_KEY || echo "CURSOR_API_KEY not found"`,
    ]);
    expect(envCheck.stdout).toContain("CURSOR_API_KEY");
  });

  test("agentapi-model-and-force-flags", async () => {
    const model = "sonnet-4";
    const { id } = await setup_agentapi_version({
      moduleVariables: {
        model: model,
        force: "true",
        ai_prompt: "test prompt",
      }
    });
    const resp = await execModuleScript(id);
    expect(resp.exitCode).toBe(0);

    const startLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.cursor-cli-module/agentapi-start.log || cat /home/coder/.cursor-cli-module/start.log || true",
    ]);
    expect(startLog.stdout).toContain(`-m ${model}`);
    expect(startLog.stdout).toContain("-f");
    expect(startLog.stdout).toContain("test prompt");
  });

  test("agentapi-pre-post-install-scripts", async () => {
    const { id } = await setup_agentapi_version({
      moduleVariables: {
        pre_install_script: "#!/bin/bash\necho 'cursor-pre-install-script'",
        post_install_script: "#!/bin/bash\necho 'cursor-post-install-script'",
      }
    });
    const resp = await execModuleScript(id);
    expect(resp.exitCode).toBe(0);

    const preInstallLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.cursor-cli-module/pre_install.log || true",
    ]);
    expect(preInstallLog.stdout).toContain("cursor-pre-install-script");

    const postInstallLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.cursor-cli-module/post_install.log || true",
    ]);
    expect(postInstallLog.stdout).toContain("cursor-post-install-script");
  });

  test("agentapi-folder-variable", async () => {
    const folder = "/tmp/cursor-test-folder";
    const { id } = await setup_agentapi_version({
      moduleVariables: {
        folder: folder,
      }
    });
    const resp = await execModuleScript(id);
    expect(resp.exitCode).toBe(0);

    const installLog = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.cursor-cli-module/install.log || true",
    ]);
    expect(installLog.stdout).toContain(folder);
  });

  // test end for the agentapi module version

  test("install-test-cursor-cli-latest", async () => {
    const { id } = await setup_agentapi_version({
      skipCursorCliMock: true,
      skipAgentAPIMock: true,
    });
    const resp = await execModuleScript(id);
    expect(resp.exitCode).toBe(0);

    await expectAgentAPIStarted(id);
  })

});


