import { serve } from "bun";
import {
  afterEach,
  beforeAll,
  describe,
  expect,
  it,
  setDefaultTimeout,
} from "bun:test";
import {
  createJSONResponse,
  execContainer,
  findResourceInstance,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  writeCoder,
} from "~test";

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

const setupContainer = async (
  image = "lorello/alpine-bash",
  vars: Record<string, string> = {},
) => {
  const server = setupServer();
  const state = await runTerraformApply(import.meta.dir, {
    agent_id: "foo",
    ...vars,
  });
  const instance = findResourceInstance(state, "coder_script");
  const id = await runContainer(image);

  registerCleanup(async () => {
    server.stop();
  });
  registerCleanup(async () => {
    await removeContainer(id);
  });

  return { id, instance, server };
};

const setupServer = () => {
  const fakeGithubHost = serve({
    fetch: (req) => {
      const url = new URL(req.url);
      if (url.pathname === "/api/v2/users/me/gitsshkey") {
        return createJSONResponse({
          public_key: "exists",
        });
      }

      if (url.pathname === "/user/keys") {
        if (req.method === "POST") {
          return createJSONResponse(
            {
              key: "created",
            },
            201,
          );
        }

        // case: key already exists
        if (req.headers.get("Authorization") === "Bearer findkey") {
          return createJSONResponse([
            {
              key: "foo",
            },
            {
              key: "exists",
            },
          ]);
        }

        // case: key does not exist
        return createJSONResponse([
          {
            key: "foo",
          },
        ]);
      }

      return createJSONResponse(
        {
          error: "not_found",
        },
        404,
      );
    },
    port: 0,
  });

  return fakeGithubHost;
};

setDefaultTimeout(30 * 1000);

describe("github-upload-public-key", () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("creates new key if one does not exist", async () => {
    const { instance, id, server } = await setupContainer();
    await writeCoder(id, "echo foo");

    const url = server.url.toString().slice(0, -1);
    const exec = await execContainer(id, [
      "env",
      `CODER_ACCESS_URL=${url}`,
      `GITHUB_API_URL=${url}`,
      "CODER_OWNER_SESSION_TOKEN=foo",
      "CODER_EXTERNAL_AUTH_ID=github",
      "bash",
      "-c",
      instance.script,
    ]);
    expect(exec.stdout).toContain(
      "Your Coder public key has been added to GitHub!",
    );
    expect(exec.exitCode).toBe(0);
  });

  it("does nothing if one already exists", async () => {
    const { instance, id, server } = await setupContainer();
    // use keyword to make server return a existing key
    await writeCoder(id, "echo findkey");

    const url = server.url.toString().slice(0, -1);
    const exec = await execContainer(id, [
      "env",
      `CODER_ACCESS_URL=${url}`,
      `GITHUB_API_URL=${url}`,
      "CODER_OWNER_SESSION_TOKEN=foo",
      "CODER_EXTERNAL_AUTH_ID=github",
      "bash",
      "-c",
      instance.script,
    ]);
    expect(exec.stdout).toContain(
      "Your Coder public key is already on GitHub!",
    );
    expect(exec.exitCode).toBe(0);
  });
});
