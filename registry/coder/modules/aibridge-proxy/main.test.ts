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
  execContainer,
  findResourceInstance,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
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

const FAKE_CERT =
  "-----BEGIN CERTIFICATE-----\nMIIBfakecert\n-----END CERTIFICATE-----\n";

// Runs terraform apply to render the setup script, then starts a Docker
// container where we can execute it against a mock server.
const setupContainer = async (vars: Record<string, string> = {}) => {
  const state = await runTerraformApply(import.meta.dir, {
    agent_id: "foo",
    proxy_url: "https://aiproxy.example.com",
    ...vars,
  });
  const instance = findResourceInstance(state, "coder_script");
  const id = await runContainer("lorello/alpine-bash");

  registerCleanup(async () => {
    await removeContainer(id);
  });

  return { id, instance };
};

// Starts a mock HTTP server that simulates the Coder API certificate endpoint.
// Returns the server and its base URL.
const setupServer = (handler: (req: Request) => Response) => {
  const server = serve({
    fetch: handler,
    port: 0,
  });
  registerCleanup(async () => {
    server.stop();
  });
  return {
    server,
    // Base URL without trailing slash
    url: server.url.toString().slice(0, -1),
  };
};

setDefaultTimeout(30 * 1000);

describe("aibridge-proxy", () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  // Verify that agent_id and proxy_url are required.
  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
    proxy_url: "https://aiproxy.example.com",
  });

  it("downloads the CA certificate successfully", async () => {
    let receivedToken = "";
    const { url } = setupServer((req) => {
      const reqUrl = new URL(req.url);
      if (reqUrl.pathname === "/api/v2/aibridge/proxy/ca-cert.pem") {
        receivedToken = req.headers.get("Coder-Session-Token") || "";
        return new Response(FAKE_CERT, {
          status: 200,
          headers: { "Content-Type": "application/x-pem-file" },
        });
      }
      return new Response("not found", { status: 404 });
    });

    const { id, instance } = await setupContainer();

    // Override ACCESS_URL and SESSION_TOKEN at runtime to point at the mock server.
    const exec = await execContainer(id, [
      "env",
      `ACCESS_URL=${url}`,
      "SESSION_TOKEN=test-session-token-123",
      "bash",
      "-c",
      instance.script,
    ]);
    expect(exec.exitCode).toBe(0);
    expect(exec.stdout).toContain(
      "AI Bridge Proxy CA certificate saved to /tmp/aibridge-proxy/ca-cert.pem",
    );

    // Verify the cert was written to the default path.
    const certContent = await execContainer(id, [
      "cat",
      "/tmp/aibridge-proxy/ca-cert.pem",
    ]);
    expect(certContent.stdout).toContain("BEGIN CERTIFICATE");

    // Verify the session token was sent in the request header.
    expect(receivedToken).toBe("test-session-token-123");
  });

  it("fails when the server is unreachable", async () => {
    const { id, instance } = await setupContainer();

    // Port 9999 has nothing listening, so curl will fail to connect.
    const exec = await execContainer(id, [
      "env",
      "ACCESS_URL=http://localhost:9999",
      "SESSION_TOKEN=mock-token",
      "bash",
      "-c",
      instance.script,
    ]);
    expect(exec.exitCode).not.toBe(0);
    expect(exec.stdout).toContain(
      "AI Bridge Proxy setup failed: could not connect to",
    );
  });

  it("fails when the server returns a non-200 status", async () => {
    const { url } = setupServer(() => {
      return new Response("not found", { status: 404 });
    });

    const { id, instance } = await setupContainer();

    const exec = await execContainer(id, [
      "env",
      `ACCESS_URL=${url}`,
      "SESSION_TOKEN=mock-token",
      "bash",
      "-c",
      instance.script,
    ]);
    expect(exec.exitCode).not.toBe(0);
    expect(exec.stdout).toContain(
      "AI Bridge Proxy setup failed: unexpected response",
    );
  });

  it("fails when the server returns an empty response", async () => {
    const { url } = setupServer((req) => {
      const reqUrl = new URL(req.url);
      if (reqUrl.pathname === "/api/v2/aibridge/proxy/ca-cert.pem") {
        return new Response("", { status: 200 });
      }
      return new Response("not found", { status: 404 });
    });

    const { id, instance } = await setupContainer();

    const exec = await execContainer(id, [
      "env",
      `ACCESS_URL=${url}`,
      "SESSION_TOKEN=mock-token",
      "bash",
      "-c",
      instance.script,
    ]);
    expect(exec.exitCode).not.toBe(0);
    expect(exec.stdout).toContain(
      "AI Bridge Proxy setup failed: downloaded certificate is empty.",
    );
  });

  it("saves the certificate to a custom path", async () => {
    const { url } = setupServer((req) => {
      const reqUrl = new URL(req.url);
      if (reqUrl.pathname === "/api/v2/aibridge/proxy/ca-cert.pem") {
        return new Response(FAKE_CERT, {
          status: 200,
          headers: { "Content-Type": "application/x-pem-file" },
        });
      }
      return new Response("not found", { status: 404 });
    });

    // Pass a custom cert_path to terraform apply so the script uses it.
    const { id, instance } = await setupContainer({
      cert_path: "/tmp/custom/certs/proxy-ca.pem",
    });

    const exec = await execContainer(id, [
      "env",
      `ACCESS_URL=${url}`,
      "SESSION_TOKEN=mock-token",
      "bash",
      "-c",
      instance.script,
    ]);
    expect(exec.exitCode).toBe(0);
    expect(exec.stdout).toContain(
      "AI Bridge Proxy CA certificate saved to /tmp/custom/certs/proxy-ca.pem",
    );

    const certContent = await execContainer(id, [
      "cat",
      "/tmp/custom/certs/proxy-ca.pem",
    ]);
    expect(certContent.stdout).toContain("BEGIN CERTIFICATE");
  });

  it("does not create global proxy env vars via coder_env", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "foo",
      proxy_url: "https://aiproxy.example.com",
    });

    // Proxy env vars should NOT be set globally via coder_env.
    // They are intended to be scoped to specific tool processes.
    const proxyEnvVarNames = [
      "HTTP_PROXY",
      "HTTPS_PROXY",
      "NODE_EXTRA_CA_CERTS",
      "SSL_CERT_FILE",
      "REQUESTS_CA_BUNDLE",
      "CURL_CA_BUNDLE",
    ];
    const proxyEnvVars = state.resources.filter(
      (r) =>
        r.type === "coder_env" &&
        r.instances.some((i) =>
          proxyEnvVarNames.includes(i.attributes.name as string),
        ),
    );
    expect(proxyEnvVars.length).toBe(0);
  });
});
