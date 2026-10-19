import {
  execContainer,
  loadTestFile,
  setupContainer,
  writeExecutable,
} from "~test";
import { expect } from "bun:test";

// Generic helpers live in ~test. They are re-exported here for modules that
// still import them from this file.
export {
  execModuleScript,
  extractCoderEnvVars,
  loadTestFile,
  setupContainer,
  writeExecutable,
} from "~test";

interface SetupProps {
  skipAgentAPIMock?: boolean;
  moduleDir: string;
  moduleVariables: Record<string, string>;
  projectDir?: string;
  registerCleanup: (cleanup: () => Promise<void>) => void;
  agentapiMockScript?: string;
}

export const setup = async (
  props: SetupProps,
): Promise<{ id: string; coderEnvVars: Record<string, string> }> => {
  const projectDir = props.projectDir ?? "/home/coder/project";
  const { id, coderScript, coderEnvVars, cleanup } = await setupContainer({
    moduleDir: props.moduleDir,
    vars: props.moduleVariables,
  });
  props.registerCleanup(cleanup);
  await execContainer(id, ["bash", "-c", `mkdir -p '${projectDir}'`]);
  if (!props?.skipAgentAPIMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/agentapi",
      content:
        props.agentapiMockScript ??
        (await loadTestFile(import.meta.dir, "agentapi-mock.js")),
    });
  }
  await writeExecutable({
    containerId: id,
    filePath: "/home/coder/script.sh",
    content: coderScript.script,
  });
  return { id, coderEnvVars };
};

export const expectAgentAPIStarted = async (
  id: string,
  port: number = 3284,
) => {
  const resp = await execContainer(id, [
    "bash",
    "-c",
    `curl -fs -o /dev/null "http://localhost:${port}/status"`,
  ]);
  if (resp.exitCode !== 0) {
    console.log("agentapi not started");
    console.log(resp.stdout);
    console.log(resp.stderr);
  }
  expect(resp.exitCode).toBe(0);
};
