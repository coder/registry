import {
  execContainer,
  findResourceInstance,
  removeContainer,
  runContainer,
  runTerraformApply,
  TerraformState,
  writeFileContainer,
} from "~test";
import path from "path";
import { expect } from "bun:test";

/**
 * Extracts all coder_env resources from Terraform state and returns them as
 * a Record of environment variable names to values.
 */
export const extractCoderEnvVars = (
  state: TerraformState,
): Record<string, string> => {
  const envVars: Record<string, string> = {};

  for (const resource of state.resources) {
    if (resource.type === "coder_env" && resource.instances.length > 0) {
      const instance = resource.instances[0].attributes;
      const name = instance.name as string;
      const value = instance.value as string;
      if (name && value) {
        envVars[name] = value;
      }
    }
  }

  return envVars;
};

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
  const coderEnvVars = extractCoderEnvVars(state);
  const id = await runContainer(image ?? "codercom/enterprise-node:latest");
  return {
    id,
    coderScript,
    coderEnvVars,
    cleanup: async () => {
      if (
        process.env["DEBUG"] === "true" ||
        process.env["DEBUG"] === "1" ||
        process.env["DEBUG"] === "yes"
      ) {
        console.log(`Not removing container ${id} in debug mode`);
        console.log(`Run "docker rm -f ${id}" to remove it manually.`);
      } else {
        await removeContainer(id);
      }
    },
  };
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
  await execContainer(
    containerId,
    ["bash", "-c", `chmod 755 ${filePath}`],
    ["--user", "root"],
  );
};

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

export const execModuleScript = async (
  id: string,
  env?: Record<string, string>,
) => {
  const envArgs = env
    ? Object.entries(env)
        .map(([key, value]) => `export ${key}="${value.replace(/"/g, '\\"')}"`)
        .join(" && ") + " && "
    : "";
  const resp = await execContainer(id, [
    "bash",
    "-c",
    `${envArgs}set -o errexit; set -o pipefail; cd /home/coder && ./script.sh 2>&1 | tee /home/coder/script.log`,
  ]);
  if (resp.exitCode !== 0) {
    console.log(resp.stdout);
    console.log(resp.stderr);
  }
  return resp;
};
