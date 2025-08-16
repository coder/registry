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

interface SetupProps {
  skipAgentAPIMock?: boolean;
  skipCursorCliMock?: boolean;
  moduleVariables?: Record<string, string>;
  agentapiMockScript?: string;
}

const setup = async (props?: SetupProps): Promise<{ id: string }> => {
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

  test("agentapi-happy-path", async () => {
    const { id } = await setup({});
    const resp = await execModuleScript(id);
    expect(resp.exitCode).toBe(0);

    await expectAgentAPIStarted(id);
  });

  test("agentapi-mcp-json", async () => {
    const mcpJson = '{"mcpServers": {"test": {"command": "test-cmd", "type": "stdio"}}}';
    const { id } = await setup({
      moduleVariables: {
        mcp: mcpJson,
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
    const { id } = await setup({
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
    const { id } = await setup({
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
    const { id } = await setup({
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
    const { id } = await setup({
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
    const { id } = await setup({
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

  test("install-test-cursor-cli-latest", async () => {
    const { id } = await setup({
      skipCursorCliMock: true,
      skipAgentAPIMock: true,
    });
    const resp = await execModuleScript(id);
    expect(resp.exitCode).toBe(0);

    await expectAgentAPIStarted(id);
  })

});


