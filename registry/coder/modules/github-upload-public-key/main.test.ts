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

const setupServer = () => {
  return serve({
    fetch: (req) => {
      const url = new URL(req.url);
      if (url.pathname === "/api/v2/users/me/gitsshkey") {
        return createJSONResponse({ public_key: "exists" });
      }
      if (url.pathname === "/user/keys") {
        if (req.method === "POST") {
          return createJSONResponse({ key: "created" }, 201);
        }
        // key already exists when the token is "findkey"
        if (req.headers.get("Authorization") === "Bearer findkey") {
          return createJSONResponse([{ key: "foo" }, { key: "exists" }]);
        }
        return createJSONResponse([{ key: "foo" }]);
      }
      return createJSONResponse({ error: "not_found" }, 404);
    },
    port: 0,
  });
};

const setupContainer = async (
  githubToken: string,
  image = "lorello/alpine-bash",
  vars: Record<string, string> = {},
) => {
  const server = setupServer();
  const url = server.url.toString().slice(0, -1);

  const state = await runTerraformApply(import.meta.dir, {
    agent_id: "foo",
    github_api_url: url,
    coder_access_url: url,
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

  // Mock coder binary: return the GitHub token for external-auth, exit 0 for
  // everything else (exp sync start/complete).
  await writeCoder(
    id,
    `#!/bin/bash
if [ "$1" = "external-auth" ]; then
  echo "${githubToken}"
fi
exit 0
`,
  );

  // Write the coder_utils wrapper to a temp file and run it, matching the
  // codex/claude-code test pattern so that baked-in URLs are exercised directly.
  const scriptPath = "/tmp/github-upload-public-key-install.sh";
  const exec = await execContainer(id, [
    "bash",
    "-c",
    `cat > '${scriptPath}' << 'WRAPPER_EOF'\n${instance.script}\nWRAPPER_EOF\nchmod +x '${scriptPath}'\n'${scriptPath}'`,
  ]);

  return { id, exec, server };
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
    const { exec } = await setupContainer("foo");
    expect(exec.stdout).toContain(
      "Your Coder public key has been added to GitHub!",
    );
    expect(exec.exitCode).toBe(0);
  });

  it("does nothing if one already exists", async () => {
    const { exec } = await setupContainer("findkey");
    expect(exec.stdout).toContain("Your Coder public key is already on GitHub!");
    expect(exec.exitCode).toBe(0);
  });
});
