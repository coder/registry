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

type Upload = { path: string; title: string };

const AUTH_KEYS_PATH = "/user/keys";
const SIGNING_KEYS_PATH = "/user/ssh_signing_keys";

const setupContainer = async (
  image = "lorello/alpine-bash",
  vars: Record<string, string> = {},
) => {
  const { server, uploads } = setupServer();
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

  const url = server.url.toString().slice(0, -1);
  const run = () =>
    execContainer(id, [
      "env",
      `CODER_ACCESS_URL=${url}`,
      `GITHUB_API_URL=${url}`,
      "CODER_OWNER_SESSION_TOKEN=foo",
      "CODER_EXTERNAL_AUTH_ID=github",
      "bash",
      "-c",
      instance.script,
    ]);

  return { id, url, run, uploads };
};

const setupServer = () => {
  const uploads: Upload[] = [];
  const server = serve({
    fetch: async (req) => {
      const url = new URL(req.url);
      if (url.pathname === "/api/v2/users/me/gitsshkey") {
        return createJSONResponse({
          public_key: "exists",
        });
      }

      if (
        url.pathname === AUTH_KEYS_PATH ||
        url.pathname === SIGNING_KEYS_PATH
      ) {
        if (req.method === "POST") {
          const body = (await req.json()) as { title: string };
          uploads.push({ path: url.pathname, title: body.title });
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

  return { server, uploads };
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
    const { id, url, run, uploads } = await setupContainer();
    await writeCoder(id, "echo foo");

    const exec = await run();
    expect(exec.stdout).toContain(
      "Your Coder public key has been added as a GitHub authentication key!",
    );
    expect(exec.exitCode).toBe(0);
    expect(uploads).toEqual([
      { path: AUTH_KEYS_PATH, title: `${url} Workspaces` },
    ]);
  });

  it("uses a custom key name", async () => {
    const keyName = "ACME Coder Workspaces";
    const { id, run, uploads } = await setupContainer(undefined, {
      key_name: keyName,
    });
    await writeCoder(id, "echo foo");

    const exec = await run();
    expect(exec.stdout).toContain(
      "Your Coder public key has been added as a GitHub authentication key!",
    );
    expect(exec.exitCode).toBe(0);
    expect(uploads).toEqual([{ path: AUTH_KEYS_PATH, title: keyName }]);
  });

  it("uses a key name with special characters", async () => {
    const keyName = 'Special $(id) "chars" `test`';
    const { id, run, uploads } = await setupContainer(undefined, {
      key_name: keyName,
    });
    await writeCoder(id, "echo foo");

    const exec = await run();
    expect(exec.stdout).toContain(
      "Your Coder public key has been added as a GitHub authentication key!",
    );
    expect(exec.exitCode).toBe(0);
    expect(uploads).toEqual([{ path: AUTH_KEYS_PATH, title: keyName }]);
  });

  it("does nothing if one already exists", async () => {
    const { id, run, uploads } = await setupContainer();
    // use keyword to make server return a existing key
    await writeCoder(id, "echo findkey");

    const exec = await run();
    expect(exec.stdout).toContain(
      "Your Coder public key is already a GitHub authentication key!",
    );
    expect(exec.exitCode).toBe(0);
    expect(uploads).toEqual([]);
  });

  it("uploads only a signing key when key_type is signing", async () => {
    const { id, url, run, uploads } = await setupContainer(undefined, {
      key_type: "signing",
    });
    await writeCoder(id, "echo foo");

    const exec = await run();
    expect(exec.stdout).toContain(
      "Your Coder public key has been added as a GitHub signing key!",
    );
    expect(exec.exitCode).toBe(0);
    expect(uploads).toEqual([
      { path: SIGNING_KEYS_PATH, title: `${url} Workspaces` },
    ]);
  });

  it("uploads authentication and signing keys when key_type is both", async () => {
    const { id, url, run, uploads } = await setupContainer(undefined, {
      key_type: "both",
    });
    await writeCoder(id, "echo foo");

    const exec = await run();
    expect(exec.stdout).toContain(
      "Your Coder public key has been added as a GitHub authentication key!",
    );
    expect(exec.stdout).toContain(
      "Your Coder public key has been added as a GitHub signing key!",
    );
    expect(exec.exitCode).toBe(0);
    expect(uploads).toEqual([
      { path: AUTH_KEYS_PATH, title: `${url} Workspaces` },
      { path: SIGNING_KEYS_PATH, title: `${url} Workspaces` },
    ]);
  });

  it("skips existing keys when key_type is both", async () => {
    const { id, run, uploads } = await setupContainer(undefined, {
      key_type: "both",
    });
    await writeCoder(id, "echo findkey");

    const exec = await run();
    expect(exec.stdout).toContain(
      "Your Coder public key is already a GitHub authentication key!",
    );
    expect(exec.stdout).toContain(
      "Your Coder public key is already a GitHub signing key!",
    );
    expect(exec.exitCode).toBe(0);
    expect(uploads).toEqual([]);
  });
});
