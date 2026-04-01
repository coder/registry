import { describe, expect, it } from "bun:test";
import {
  execContainer,
  findResourceInstance,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
  type TerraformState,
} from "~test";

interface TestFixture {
  state: TerraformState;
  server: ReturnType<typeof Bun.serve>;
  [Symbol.asyncDispose](): Promise<void>;
}

interface ContainerHandle {
  id: string;
  [Symbol.asyncDispose](): Promise<void>;
}

async function setupContainer(image: string): Promise<ContainerHandle> {
  const id = await runContainer(image);
  return {
    id,
    [Symbol.asyncDispose]: async () => {
      await removeContainer(id);
    },
  };
}

const ENV_PREFIX =
  'export CODER_SCRIPT_DATA_DIR=/tmp/coder-script-data && export CODER_SCRIPT_BIN_DIR=/tmp/coder-script-data/bin && mkdir -p "$CODER_SCRIPT_DATA_DIR" "$CODER_SCRIPT_BIN_DIR" && ';

async function setupFakeBinaryServer(
  dir: string,
  extraVars?: Record<string, string>,
): Promise<TestFixture> {
  const fakeBinary = "#!/bin/sh\necho portabledesktop";
  const server = Bun.serve({
    port: 0,
    fetch() {
      return new Response(fakeBinary);
    },
  });

  const state = await runTerraformApply(dir, {
    agent_id: "foo",
    url: `http://localhost:${server.port}/portabledesktop`,
    ...extraVars,
  });

  return {
    state,
    server,
    [Symbol.asyncDispose]: async () => {
      server.stop(true);
    },
  };
}

describe("portabledesktop", async () => {
  await runTerraformInit(import.meta.dir);

  testRequiredVariables(import.meta.dir, {
    agent_id: "foo",
  });

  it("installs portabledesktop successfully", async () => {
    await using fixture = await setupFakeBinaryServer(import.meta.dir);
    await using container = await setupContainer("alpine/curl");

    const script = findResourceInstance(fixture.state, "coder_script").script;
    const resp = await execContainer(container.id, [
      "sh",
      "-c",
      ENV_PREFIX + script,
    ]);

    expect(resp.exitCode).toBe(0);
    expect(resp.stdout).toContain("portabledesktop installed successfully");

    // Check binary exists at CODER_SCRIPT_DATA_DIR.
    const checkBinary = await execContainer(container.id, [
      "test",
      "-x",
      "/tmp/coder-script-data/portabledesktop",
    ]);
    expect(checkBinary.exitCode).toBe(0);

    // Check symlink exists at CODER_SCRIPT_BIN_DIR.
    const checkSymlink = await execContainer(container.id, [
      "test",
      "-L",
      "/tmp/coder-script-data/bin/portabledesktop",
    ]);
    expect(checkSymlink.exitCode).toBe(0);
  }, 30000);

  it("verifies checksum when sha256 is provided", async () => {
    const fakeBinary = "#!/bin/sh\necho portabledesktop";
    const hasher = new Bun.CryptoHasher("sha256");
    hasher.update(fakeBinary);
    const sha256 = hasher.digest("hex");

    await using fixture = await setupFakeBinaryServer(import.meta.dir, {
      sha256,
    });
    await using container = await setupContainer("alpine/curl");

    const script = findResourceInstance(fixture.state, "coder_script").script;
    const resp = await execContainer(container.id, [
      "sh",
      "-c",
      ENV_PREFIX + script,
    ]);

    expect(resp.exitCode).toBe(0);
    expect(resp.stdout).toContain("Checksum verified successfully");
    expect(resp.stdout).toContain("portabledesktop installed successfully");
  }, 30000);

  it("fails when sha256 does not match", async () => {
    const wrongSha256 =
      "0000000000000000000000000000000000000000000000000000000000000000";

    await using fixture = await setupFakeBinaryServer(import.meta.dir, {
      sha256: wrongSha256,
    });
    await using container = await setupContainer("alpine/curl");

    const script = findResourceInstance(fixture.state, "coder_script").script;
    const resp = await execContainer(container.id, [
      "sh",
      "-c",
      ENV_PREFIX + script,
    ]);

    expect(resp.exitCode).toBe(1);
    expect(resp.stdout).toContain("Checksum mismatch");
  }, 30000);

  it("skips checksum verification when sha256 is not set", async () => {
    await using fixture = await setupFakeBinaryServer(import.meta.dir);
    await using container = await setupContainer("alpine/curl");

    const script = findResourceInstance(fixture.state, "coder_script").script;
    const resp = await execContainer(container.id, [
      "sh",
      "-c",
      ENV_PREFIX + script,
    ]);

    expect(resp.exitCode).toBe(0);
    expect(resp.stdout).not.toContain("Checksum verified");
    expect(resp.stdout).toContain("portabledesktop installed successfully");
  }, 30000);

  it("falls back to sudo when install_dir is not writable", async () => {
    await using fixture = await setupFakeBinaryServer(import.meta.dir, {
      install_dir: "/usr/local/bin",
    });
    await using container = await setupContainer("alpine/curl");

    await execContainer(container.id, [
      "sh",
      "-c",
      "apk add sudo && " +
        "adduser -D testuser && " +
        "echo 'testuser ALL=(ALL) NOPASSWD: ALL' >> /etc/sudoers && " +
        "mkdir -p /usr/local/bin",
    ]);

    const script = findResourceInstance(fixture.state, "coder_script").script;
    const resp = await execContainer(
      container.id,
      ["sh", "-c", ENV_PREFIX + script],
      ["--user", "testuser"],
    );

    expect(resp.exitCode).toBe(0);
    expect(resp.stdout).toContain("via sudo");
    expect(resp.stdout).toContain("portabledesktop installed successfully");

    // Verify the binary was copied to the install_dir.
    const check = await execContainer(container.id, [
      "test",
      "-x",
      "/usr/local/bin/portabledesktop",
    ]);
    expect(check.exitCode).toBe(0);
  }, 30000);

  it("creates install_dir if it does not exist", async () => {
    await using fixture = await setupFakeBinaryServer(import.meta.dir, {
      install_dir: "/opt/custom/bin",
    });
    await using container = await setupContainer("alpine/curl");

    const script = findResourceInstance(fixture.state, "coder_script").script;
    const resp = await execContainer(container.id, [
      "sh",
      "-c",
      ENV_PREFIX + script,
    ]);

    expect(resp.exitCode).toBe(0);
    expect(resp.stdout).toContain("portabledesktop installed successfully");

    const check = await execContainer(container.id, [
      "test",
      "-x",
      "/opt/custom/bin/portabledesktop",
    ]);
    expect(check.exitCode).toBe(0);
  }, 30000);

  it("falls back to wget when curl is not available", async () => {
    await using fixture = await setupFakeBinaryServer(import.meta.dir);
    await using container = await setupContainer("alpine");

    // Install wget but ensure curl is not present.
    await execContainer(container.id, [
      "sh",
      "-c",
      "apk add wget && ! command -v curl",
    ]);

    const script = findResourceInstance(fixture.state, "coder_script").script;
    const resp = await execContainer(container.id, [
      "sh",
      "-c",
      ENV_PREFIX + script,
    ]);

    expect(resp.exitCode).toBe(0);
    expect(resp.stdout).toContain("via wget");
    expect(resp.stdout).toContain("portabledesktop installed successfully");
  }, 30000);
});
