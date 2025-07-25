import {
  execContainer,
  findResourceInstance,
  removeContainer,
  runContainer,
  runTerraformApply,
  writeFileContainer,
} from "~test";
import path from "path";
import { expect } from "bun:test";

export const setupContainer = async ({
  moduleDir,
  image,
  vars,
}: {
  moduleDir: string;
  image?: string;
  vars?: Record<string, string>;
}) => {
  const state = await runTerraformApply(moduleDir, {
    agent_id: "foo",
    ...vars,
  });
  const coderScript = findResourceInstance(state, "coder_script");
  const id = await runContainer(image ?? "codercom/enterprise-node:latest");
  return { id, coderScript, cleanup: () => removeContainer(id) };
};

export const loadTestFile = async (
  moduleDir: string,
  ...relativePath: [string, ...string[]]
) => {
  return await Bun.file(
    path.join(moduleDir, "testdata", ...relativePath),
  ).text();
};

export const writeExecutable = async ({
  containerId,
  filePath,
  content,
}: {
  containerId: string;
  filePath: string;
  content: string;
}) => {
  await writeFileContainer(containerId, filePath, content, {
    user: "root",
  });
  await execContainer(containerId, ["chmod", "+x", filePath], ["--user", "root"]);
};

export const execModuleScript = async ({
  containerId,
  coderScript,
  userArgs,
}: {
  containerId: string;
  coderScript: { script: string };
  userArgs?: string[];
}) => {
  const scriptPath = "/tmp/module_script.sh";
  await writeExecutable({
    containerId,
    filePath: scriptPath,
    content: coderScript.script,
  });
  return await execContainer(containerId, [scriptPath, ...(userArgs ?? [])]);
};

export const expectAgentAPIStarted = async ({
  containerId,
  port = 3284,
  timeout = 30000,
}: {
  containerId: string;
  port?: number;
  timeout?: number;
}) => {
  const startTime = Date.now();
  while (Date.now() - startTime < timeout) {
    const result = await execContainer(containerId, [
      "curl",
      "-f",
      "-s",
      "-o",
      "/dev/null",
      `http://localhost:${port}/status`,
    ]);
    if (result.exitCode === 0) {
      return;
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  throw new Error(`AgentAPI did not start within ${timeout}ms`);
};

export const expectCodexCLIInstalled = async ({
  containerId,
}: {
  containerId: string;
}) => {
  const result = await execContainer(containerId, ["which", "codex-cli"]);
  expect(result.exitCode).toBe(0);
};

export const expectCodexConfigExists = async ({
  containerId,
}: {
  containerId: string;
}) => {
  const result = await execContainer(containerId, [
    "test",
    "-f",
    "/home/coder/.config/codex/config.toml",
  ]);
  expect(result.exitCode).toBe(0);
};

export const expectCodexAgentAPIBridgeExists = async ({
  containerId,
}: {
  containerId: string;
}) => {
  const result = await execContainer(containerId, [
    "test",
    "-f",
    "/home/coder/.local/bin/codex-agentapi-bridge",
  ]);
  expect(result.exitCode).toBe(0);
};
