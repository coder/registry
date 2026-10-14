import { readableStreamToText, spawn } from "bun";
import { expect, it } from "bun:test";
import { readFile, unlink } from "node:fs/promises";
import { join } from "node:path";

export const runContainer = async (
  image: string,
  init = "sleep infinity",
): Promise<string> => {
  const proc = spawn([
    "docker",
    "run",
    "--rm",
    "-d",
    "--label",
    "modules-test=true",
    "--network",
    "host",
    "--entrypoint",
    "sh",
    image,
    "-c",
    init,
  ]);

  const containerID = await readableStreamToText(proc.stdout);
  const exitCode = await proc.exited;
  if (exitCode !== 0) {
    throw new Error(containerID);
  }
  return containerID.trim();
};

export const removeContainer = async (id: string) => {
  const proc = spawn(["docker", "rm", "-f", id], {
    stderr: "pipe",
    stdout: "pipe",
  });
  const exitCode = await proc.exited;
  const [stderr, stdout] = await Promise.all([
    readableStreamToText(proc.stderr ?? new ReadableStream()),
    readableStreamToText(proc.stdout ?? new ReadableStream()),
  ]);
  if (exitCode !== 0) {
    throw new Error(`${stderr}\n${stdout}`);
  }
};

export interface scriptOutput {
  exitCode: number;
  stdout: string[];
  stderr: string[];
}

/**
 * Finds the only "coder_script" resource in the given state and runs it in a
 * container.
 */
export const executeScriptInContainer = async (
  state: TerraformState,
  image: string,
  shell = "sh",
  before?: string,
): Promise<scriptOutput> => {
  const instance = findResourceInstance(state, "coder_script");
  const id = await runContainer(image);

  if (before) {
    await execContainer(id, [shell, "-c", before]);
  }

  const resp = await execContainer(id, [shell, "-c", instance.script]);
  const stdout = resp.stdout.trim().split("\n");
  const stderr = resp.stderr.trim().split("\n");
  return {
    exitCode: resp.exitCode,
    stdout,
    stderr,
  };
};

export const execContainer = async (
  id: string,
  cmd: string[],
  args?: string[],
): Promise<{
  exitCode: number;
  stderr: string;
  stdout: string;
}> => {
  const proc = spawn(["docker", "exec", ...(args ?? []), id, ...cmd], {
    stderr: "pipe",
    stdout: "pipe",
  });
  const [stderr, stdout] = await Promise.all([
    readableStreamToText(proc.stderr),
    readableStreamToText(proc.stdout),
  ]);
  const exitCode = await proc.exited;
  return {
    exitCode,
    stderr,
    stdout,
  };
};

type JsonValue =
  | string
  | number
  | boolean
  | null
  | JsonValue[]
  | { [key: string]: JsonValue };

type TerraformStateResource = {
  module: string;
  mode: string;
  type: string;
  name: string;
  provider: string;

  instances: [
    {
      attributes: Record<string, JsonValue>;
    },
  ];
};

type TerraformOutput = {
  type: string;
  value: JsonValue;
};

export interface TerraformState {
  outputs: Record<string, TerraformOutput>;
  resources: [TerraformStateResource, ...TerraformStateResource[]];
}

type TerraformVariables = Record<string, JsonValue>;

export interface CoderScriptAttributes {
  script: string;
  agent_id: string;
  url: string;
}

export type ResourceInstance<T extends string = string> =
  T extends "coder_script" ? CoderScriptAttributes : Record<string, string>;

/**
 * finds the first instance of the given resource type in the given state. If
 * name is specified, it will only find the instance with the given name.
 */
export const findResourceInstance = <T extends string>(
  state: TerraformState,
  type: T,
  name?: string,
): ResourceInstance<T> => {
  const resource = state.resources.find(
    (resource) =>
      resource.type === type && (name ? resource.name === name : true),
  );
  if (!resource) {
    throw new Error(`Resource ${type} not found`);
  }
  if (resource.instances.length !== 1) {
    throw new Error(
      `Resource ${type} has ${resource.instances.length} instances`,
    );
  }

  return resource.instances[0].attributes as ResourceInstance<T>;
};

/**
 * Creates a test-case for each variable provided and ensures that the apply
 * fails without it.
 */
export const testRequiredVariables = <TVars extends TerraformVariables>(
  dir: string,
  vars: Readonly<TVars>,
) => {
  // Ensures that all required variables are provided.
  it("required variables", async () => {
    await runTerraformApply(dir, vars);
  });

  const varNames = Object.keys(vars);
  for (const varName of varNames) {
    // Ensures that every variable provided is required!
    it(`missing variable: ${varName}`, async () => {
      const localVars: TerraformVariables = {};
      for (const otherVarName of varNames) {
        if (otherVarName !== varName) {
          localVars[otherVarName] = vars[otherVarName];
        }
      }

      try {
        await runTerraformApply(dir, localVars);
      } catch (ex) {
        if (!(ex instanceof Error)) {
          throw new Error("Unknown error generated");
        }

        expect(ex.message).toContain(
          `input variable \"${varName}\" is not set`,
        );
        return;
      }
      throw new Error(`${varName} is not a required variable!`);
    });
  }
};

/**
 * Runs terraform apply in the given directory with the given variables. It is
 * fine to run in parallel with other instances of this function, as it uses a
 * random state file.
 */
export const runTerraformApply = async <TVars extends TerraformVariables>(
  dir: string,
  vars: Readonly<TVars>,
  customEnv?: Record<string, string>,
): Promise<TerraformState> => {
  const stateFile = `${dir}/${crypto.randomUUID()}.tfstate`;

  const childEnv: Record<string, string | undefined> = {
    ...process.env,
    ...(customEnv ?? {}),
  };

  // This is a fix for when you try to run the tests from a Coder workspace.
  // When process.env is destructured into the object, it can sometimes have
  // workspace-specific values, which causes the resulting URL to be different
  // from what the tests have classically expected.
  childEnv.CODER_AGENT_URL = undefined;
  childEnv.CODER_WORKSPACE_NAME = undefined;

  for (const [key, value] of Object.entries(vars) as [string, JsonValue][]) {
    if (value !== null) {
      childEnv[`TF_VAR_${key}`] = String(value);
    }
  }

  const proc = spawn(
    [
      "terraform",
      "apply",
      "-compact-warnings",
      "-input=false",
      "-auto-approve",
      "-no-color",
      "-state",
      stateFile,
    ],
    {
      cwd: dir,
      env: childEnv,
      stderr: "pipe",
      stdout: "pipe",
    },
  );

  const text = await readableStreamToText(proc.stderr);
  const exitCode = await proc.exited;
  if (exitCode !== 0) {
    throw new Error(text);
  }

  const content = await readFile(stateFile, "utf8");
  await unlink(stateFile);
  return JSON.parse(content);
};

/**
 * Runs terraform init in the given directory.
 */
export const runTerraformInit = async (dir: string) => {
  const proc = spawn(["terraform", "init"], {
    cwd: dir,
  });
  const text = await readableStreamToText(proc.stdout);
  const exitCode = await proc.exited;
  if (exitCode !== 0) {
    throw new Error(text);
  }
};

export const createJSONResponse = (obj: object, statusCode = 200): Response => {
  return new Response(JSON.stringify(obj), {
    headers: {
      "Content-Type": "application/json",
    },
    status: statusCode,
  });
};

export const writeCoder = async (id: string, script: string) => {
  await writeFileContainer(id, "/usr/bin/coder", script, {
    user: "root",
  });
  const execResult = await execContainer(
    id,
    ["chmod", "755", "/usr/bin/coder"],
    ["--user", "root"],
  );
  expect(execResult.exitCode).toBe(0);
};

export const writeFileContainer = async (
  id: string,
  path: string,
  content: string,
  options?: {
    user?: string;
  },
) => {
  const contentBase64 = Buffer.from(content).toString("base64");
  const proc = await execContainer(
    id,
    ["sh", "-c", `echo '${contentBase64}' | base64 -d > '${path}'`],
    options?.user ? ["--user", options.user] : undefined,
  );
  if (proc.exitCode !== 0) {
    throw new Error(`Failed to write file: ${proc.stderr}`);
  }
  expect(proc.exitCode).toBe(0);
};

export const readFileContainer = async (id: string, path: string) => {
  const proc = await execContainer(id, ["cat", path], ["--user", "root"]);
  if (proc.exitCode !== 0) {
    console.log(proc.stderr);
    console.log(proc.stdout);
  }
  expect(proc.exitCode).toBe(0);
  return proc.stdout;
};

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

/**
 * Applies the module in moduleDir, starts a container, and returns the
 * module's single coder_script, its coder_env values, and a cleanup function.
 * Containers are kept when DEBUG is set to true, 1, or yes.
 */
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

/**
 * Reads a file from the testdata directory of moduleDir.
 */
export const loadTestFile = async (
  moduleDir: string,
  ...relativePath: [string, ...string[]]
) => {
  return await Bun.file(join(moduleDir, "testdata", ...relativePath)).text();
};

/**
 * Writes content to filePath in the container as root and makes it
 * executable.
 */
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

/**
 * Runs /home/coder/script.sh in the container with the given environment and
 * tees its output to /home/coder/script.log.
 */
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
