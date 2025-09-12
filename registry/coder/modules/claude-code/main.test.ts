import {
  test,
  afterEach,
  expect,
  describe,
  it,
  setDefaultTimeout,
  beforeAll,
} from "bun:test";
import path from "path";
import {
  execContainer,
  findResourceInstance,
  readFileContainer,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  writeCoder,
  writeFileContainer,
} from "~test";

let cleanupFunctions: (() => Promise<void>)[] = [];

const registerCleanup = (cleanup: () => Promise<void>) => {
  cleanupFunctions.push(cleanup);
};

// Cleanup logic depends on the fact that bun's built-in test runner
// runs tests sequentially.
// https://bun.sh/docs/test/discovery#execution-order
// Weird things would happen if tried to run tests in parallel.
// One test could clean up resources that another test was still using.
afterEach(async () => {
  // reverse the cleanup functions so that they are run in the correct order
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

const setupContainer = async ({
  image,
  vars,
}: {
  image?: string;
  vars?: Record<string, string>;
} = {}) => {
  const state = await runTerraformApply(import.meta.dir, {
    agent_id: "foo",
    ...vars,
  });
  const coderScript = findResourceInstance(state, "coder_script");
  const id = await runContainer(image ?? "codercom/enterprise-node:latest");
  registerCleanup(() => removeContainer(id));
  return { id, coderScript };
};

const loadTestFile = async (...relativePath: string[]) => {
  return await Bun.file(
    path.join(import.meta.dir, "testdata", ...relativePath),
  ).text();
};

const writeExecutable = async ({
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

const writeAgentAPIMockControl = async ({
  containerId,
  content,
}: {
  containerId: string;
  content: string;
}) => {
  await writeFileContainer(containerId, "/tmp/agentapi-mock.control", content, {
    user: "coder",
  });
};

interface SetupProps {
  skipAgentAPIMock?: boolean;
  skipClaudeMock?: boolean;
  extraVars?: Record<string, string>;
}

const projectDir = "/home/coder/project";

const setup = async (props?: SetupProps): Promise<{ id: string }> => {
  const { id, coderScript } = await setupContainer({
    vars: {
      experiment_report_tasks: "true",
      install_agentapi: props?.skipAgentAPIMock ? "true" : "false",
      install_claude_code: "false",
      agentapi_version: "preview",
      folder: projectDir,
      ...props?.extraVars,
    },
  });
  await execContainer(id, ["bash", "-c", `mkdir -p '${projectDir}'`]);
  // the module script assumes that there is a coder executable in the PATH
  await writeCoder(id, await loadTestFile("coder-mock.js"));
  if (!props?.skipAgentAPIMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/agentapi",
      content: await loadTestFile("agentapi-mock.js"),
    });
  }
  if (!props?.skipClaudeMock) {
    await writeExecutable({
      containerId: id,
      filePath: "/usr/bin/claude",
      content: await loadTestFile("claude-mock.js"),
    });
  }
  await writeExecutable({
    containerId: id,
    filePath: "/home/coder/script.sh",
    content: coderScript.script,
  });
  return { id };
};

const expectAgentAPIStarted = async (id: string) => {
  const resp = await execContainer(id, [
    "bash",
    "-c",
    `curl -fs -o /dev/null "http://localhost:3284/status"`,
  ]);
  if (resp.exitCode !== 0) {
    console.log("agentapi not started");
    console.log(resp.stdout);
    console.log(resp.stderr);
  }
  expect(resp.exitCode).toBe(0);
};

const execModuleScript = async (id: string) => {
  const resp = await execContainer(id, [
    "bash",
    "-c",
    `set -o errexit; set -o pipefail; cd /home/coder && ./script.sh 2>&1 | tee /home/coder/script.log`,
  ]);
  if (resp.exitCode !== 0) {
    console.log(resp.stdout);
    console.log(resp.stderr);
  }
  return resp;
};

// increase the default timeout to 60 seconds
setDefaultTimeout(60 * 1000);

// we don't run these tests in CI because they take too long and make network
// calls. they are dedicated for local development.
describe("claude-code", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  // test that the script runs successfully if claude starts without any errors
  test("happy-path", async () => {
    const { id } = await setup();

    const resp = await execContainer(id, [
      "bash",
      "-c",
      "sudo /home/coder/script.sh",
    ]);
    expect(resp.exitCode).toBe(0);

    await expectAgentAPIStarted(id);
  });

  // test that the script removes lastSessionId from the .claude.json file
  test("last-session-id-removed", async () => {
    const { id } = await setup();

    await writeFileContainer(
      id,
      "/home/coder/.claude.json",
      JSON.stringify({
        projects: {
          [projectDir]: {
            lastSessionId: "123",
          },
        },
      }),
    );

    const catResp = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.claude.json",
    ]);
    expect(catResp.exitCode).toBe(0);
    expect(catResp.stdout).toContain("lastSessionId");

    const respModuleScript = await execModuleScript(id);
    expect(respModuleScript.exitCode).toBe(0);

    await expectAgentAPIStarted(id);

    const catResp2 = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.claude.json",
    ]);
    expect(catResp2.exitCode).toBe(0);
    expect(catResp2.stdout).not.toContain("lastSessionId");
  });

  // test that the script handles a .claude.json file that doesn't contain
  // a lastSessionId field
  test("last-session-id-not-found", async () => {
    const { id } = await setup();

    await writeFileContainer(
      id,
      "/home/coder/.claude.json",
      JSON.stringify({
        projects: {
          "/home/coder": {},
        },
      }),
    );

    const respModuleScript = await execModuleScript(id);
    expect(respModuleScript.exitCode).toBe(0);

    await expectAgentAPIStarted(id);

    const catResp = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/.claude-module/agentapi-start.log",
    ]);
    expect(catResp.exitCode).toBe(0);
    expect(catResp.stdout).toContain(
      "No lastSessionId found in .claude.json - nothing to do",
    );
  });

  // test that if claude fails to run with the --continue flag and returns a
  // no conversation found error, then the module script retries without the flag
  test("no-conversation-found", async () => {
    const { id } = await setup();
    await writeAgentAPIMockControl({
      containerId: id,
      content: "no-conversation-found",
    });
    // check that mocking works
    const respAgentAPI = await execContainer(id, [
      "bash",
      "-c",
      "agentapi --continue",
    ]);
    expect(respAgentAPI.exitCode).toBe(1);
    expect(respAgentAPI.stderr).toContain("No conversation found to continue");

    const respModuleScript = await execModuleScript(id);
    expect(respModuleScript.exitCode).toBe(0);

    await expectAgentAPIStarted(id);
  });

  test("install-agentapi", async () => {
    const { id } = await setup({ skipAgentAPIMock: true });

    const respModuleScript = await execModuleScript(id);
    expect(respModuleScript.exitCode).toBe(0);

    await expectAgentAPIStarted(id);
    const respAgentAPI = await execContainer(id, [
      "bash",
      "-c",
      "agentapi --version",
    ]);
    expect(respAgentAPI.exitCode).toBe(0);
  });

  // the coder binary should be executed with specific env vars
  // that are set by the module script
  test("coder-env-vars", async () => {
    const { id } = await setup();

    const respModuleScript = await execModuleScript(id);
    expect(respModuleScript.exitCode).toBe(0);

    const respCoderMock = await execContainer(id, [
      "bash",
      "-c",
      "cat /home/coder/coder-mock-output.json",
    ]);
    if (respCoderMock.exitCode !== 0) {
      console.log(respCoderMock.stdout);
      console.log(respCoderMock.stderr);
    }
    expect(respCoderMock.exitCode).toBe(0);
    expect(JSON.parse(respCoderMock.stdout)).toEqual({
      statusSlug: "ccw",
      agentApiUrl: "http://localhost:3284",
    });
  });

  // verify that the agentapi binary has access to the AGENTAPI_ALLOWED_HOSTS environment variable
  // set in main.tf
  test("agentapi-allowed-hosts", async () => {
    const { id } = await setup();

    const respModuleScript = await execModuleScript(id);
    expect(respModuleScript.exitCode).toBe(0);

    await expectAgentAPIStarted(id);

    const agentApiStartLog = await readFileContainer(
      id,
      "/home/coder/agentapi-mock.log",
    );
    expect(agentApiStartLog).toContain("AGENTAPI_ALLOWED_HOSTS=*");
  });

  describe("subdomain", async () => {
    it("sets AGENTAPI_CHAT_BASE_PATH when false", async () => {
      const { id } = await setup();
      const respModuleScript = await execModuleScript(id);
      expect(respModuleScript.exitCode).toBe(0);
      await expectAgentAPIStarted(id);
      const agentApiStartLog = await readFileContainer(
        id,
        "/home/coder/agentapi-mock.log",
      );
      expect(agentApiStartLog).toContain(
        "AGENTAPI_CHAT_BASE_PATH=/@default/default.foo/apps/ccw/chat",
      );
    });

    it("does not set AGENTAPI_CHAT_BASE_PATH when true", async () => {
      const { id } = await setup({
        extraVars: { subdomain: "true" },
      });
      const respModuleScript = await execModuleScript(id);
      expect(respModuleScript.exitCode).toBe(0);
      await expectAgentAPIStarted(id);
      const agentApiStartLog = await readFileContainer(
        id,
        "/home/coder/agentapi-mock.log",
      );
      expect(agentApiStartLog).toMatch(/AGENTAPI_CHAT_BASE_PATH=$/m);
    });
  });
});
