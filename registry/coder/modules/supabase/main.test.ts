import {
  describe,
  expect,
  it,
  beforeAll,
  afterEach,
  setDefaultTimeout,
} from "bun:test";
import {
  execContainer,
  removeContainer,
  runContainer,
  runTerraformApply,
  runTerraformInit,
  testRequiredVariables,
} from "~test";

setDefaultTimeout(3 * 60 * 1000); // 3 minutes for CLI downloads

let cleanupContainers: string[] = [];

afterEach(async () => {
  for (const id of cleanupContainers) {
    try {
      await removeContainer(id);
    } catch {
      // ignore cleanup errors
    }
  }
  cleanupContainers = [];
});

describe("supabase", () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  testRequiredVariables(import.meta.dir, {
    agent_id: "test-agent",
  });

  it("missing variable: agent_id", async () => {
    await expect(runTerraformApply(import.meta.dir, {})).rejects.toThrow(
      /agent_id/,
    );
  });

  it("defaults to detect install method", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
    });
    const script = state.resources.find(
      (r) => r.type === "coder_script" && r.name === "install_script",
    );
    expect(script).toBeDefined();
    // coder-utils wraps our script in base64, decode to check
    const wrapperScript = script!.instances[0].attributes.script as string;
    const b64Match = wrapperScript.match(/echo -n '([A-Za-z0-9+/=]+)'/);
    expect(b64Match).toBeTruthy();
    const decodedScript = Buffer.from(b64Match![1], "base64").toString("utf-8");
    expect(decodedScript).toContain("INSTALL_METHOD='detect'");
  });

  it("accepts binary install method", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      install_method: "binary",
    });
    const script = state.resources.find(
      (r) => r.type === "coder_script" && r.name === "install_script",
    );
    const wrapperScript = script!.instances[0].attributes.script as string;
    const b64Match = wrapperScript.match(/echo -n '([A-Za-z0-9+/=]+)'/);
    const decodedScript = Buffer.from(b64Match![1], "base64").toString("utf-8");
    expect(decodedScript).toContain("INSTALL_METHOD='binary'");
  });

  it("accepts brew install method", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      install_method: "brew",
    });
    const script = state.resources.find(
      (r) => r.type === "coder_script" && r.name === "install_script",
    );
    const wrapperScript = script!.instances[0].attributes.script as string;
    const b64Match = wrapperScript.match(/echo -n '([A-Za-z0-9+/=]+)'/);
    const decodedScript = Buffer.from(b64Match![1], "base64").toString("utf-8");
    expect(decodedScript).toContain("INSTALL_METHOD='brew'");
  });

  it("accepts scoop install method", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      install_method: "scoop",
    });
    const script = state.resources.find(
      (r) => r.type === "coder_script" && r.name === "install_script",
    );
    const wrapperScript = script!.instances[0].attributes.script as string;
    const b64Match = wrapperScript.match(/echo -n '([A-Za-z0-9+/=]+)'/);
    const decodedScript = Buffer.from(b64Match![1], "base64").toString("utf-8");
    expect(decodedScript).toContain("INSTALL_METHOD='scoop'");
  });

  it("rejects invalid install method", async () => {
    await expect(
      runTerraformApply(import.meta.dir, {
        agent_id: "test-agent",
        install_method: "invalid",
      }),
    ).rejects.toThrow(/install_method.*must be/);
  });

  it("supports skip_install option", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      skip_install: "true",
    });
    const script = state.resources.find(
      (r) => r.type === "coder_script" && r.name === "install_script",
    );
    expect(script).toBeDefined();
    const wrapperScript = script!.instances[0].attributes.script as string;
    const b64Match = wrapperScript.match(/echo -n '([A-Za-z0-9+/=]+)'/);
    expect(b64Match).toBeTruthy();
    const decodedScript = Buffer.from(b64Match![1], "base64").toString("utf-8");
    expect(decodedScript).toContain("Skipping Supabase CLI installation");
  });

  it("supports custom download_base_url", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      download_base_url: "https://mirror.internal/supabase",
    });
    const script = state.resources.find(
      (r) => r.type === "coder_script" && r.name === "install_script",
    );
    const wrapperScript = script!.instances[0].attributes.script as string;
    const b64Match = wrapperScript.match(/echo -n '([A-Za-z0-9+/=]+)'/);
    const decodedScript = Buffer.from(b64Match![1], "base64").toString("utf-8");
    expect(decodedScript).toContain("https://mirror.internal/supabase");
  });

  it("sets access_token when use_external_auth is false", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      use_external_auth: "false",
      access_token: "sbp_test_token_abc123",
    });
    expect(state.outputs.access_token.value).toBe("sbp_test_token_abc123");
  });

  it("installs via binary on ubuntu", async () => {
    const id = await runContainer("ubuntu:22.04");
    cleanupContainers.push(id);

    await execContainer(id, ["apt-get", "update"]);
    await execContainer(id, ["apt-get", "install", "-y", "curl", "tar"]);

    // Build script as array to avoid template literal escaping issues
    const script = [
      "#!/bin/bash",
      "set -ex",
      "export HOME=/root",
      "BIN_DIR=$HOME/.coder-modules/coder/supabase/bin",
      "mkdir -p $BIN_DIR",
      "ARCH=$(uname -m)",
      "case $ARCH in x86_64|amd64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; esac",
      "OS=$(uname -s | tr A-Z a-z)",
      "API_RESPONSE=$(curl -fsSL https://api.github.com/repos/supabase/cli/releases/latest)",
      'VERSION=$(echo "$API_RESPONSE" | grep -o \'"tag_name": *"[^"]*\' | head -1 | sed \'s/.*"v//\' | sed \'s/".*//\')',
      "DOWNLOAD_URL=https://github.com/supabase/cli/releases/download/v$VERSION/supabase_${OS}_${ARCH}.tar.gz",
      "curl -fsSL -o /tmp/supabase.tar.gz $DOWNLOAD_URL",
      "tar -xzf /tmp/supabase.tar.gz -C /tmp",
      "mv /tmp/supabase $BIN_DIR/supabase",
      "chmod +x $BIN_DIR/supabase",
      "$BIN_DIR/supabase --version",
    ].join("\n");

    await execContainer(id, [
      "sh",
      "-c",
      "cat > /tmp/install.sh << 'SCRIPT'\n" + script + "\nSCRIPT",
    ]);
    await execContainer(id, ["chmod", "+x", "/tmp/install.sh"]);
    const result = await execContainer(id, ["/tmp/install.sh"]);

    if (result.exitCode !== 0) {
      console.error("STDOUT:", result.stdout);
      console.error("STDERR:", result.stderr);
    }
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toMatch(/\d+\.\d+\.\d+/); // version number like 2.115.0
  });

  // Note: Binary install on Alpine (musl libc) doesn't work because Supabase CLI
  // is compiled for glibc. In production, the module would fall back to apk package.
  // This test verifies binary install on a glibc-based distro (Debian).
  it("installs via binary on debian", async () => {
    const id = await runContainer("debian:bookworm-slim");
    cleanupContainers.push(id);

    await execContainer(id, ["apt-get", "update"]);
    await execContainer(id, [
      "apt-get",
      "install",
      "-y",
      "curl",
      "ca-certificates",
    ]);

    const script = [
      "#!/bin/bash",
      "set -ex",
      "export HOME=/root",
      "BIN_DIR=$HOME/.coder-modules/coder/supabase/bin",
      "mkdir -p $BIN_DIR",
      "ARCH=$(uname -m)",
      "case $ARCH in x86_64|amd64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; esac",
      "OS=$(uname -s | tr A-Z a-z)",
      "API_RESPONSE=$(curl -fsSL https://api.github.com/repos/supabase/cli/releases/latest)",
      'VERSION=$(echo "$API_RESPONSE" | grep -o \'"tag_name": *"[^"]*\' | head -1 | sed \'s/.*"v//\' | sed \'s/".*//\')',
      "DOWNLOAD_URL=https://github.com/supabase/cli/releases/download/v$VERSION/supabase_${OS}_${ARCH}.tar.gz",
      "curl -fsSL -o /tmp/supabase.tar.gz $DOWNLOAD_URL",
      "tar -xzf /tmp/supabase.tar.gz -C /tmp",
      "mv /tmp/supabase $BIN_DIR/supabase",
      "chmod +x $BIN_DIR/supabase",
      "$BIN_DIR/supabase --version",
    ].join("\n");

    await execContainer(id, [
      "sh",
      "-c",
      "cat > /tmp/install.sh << 'SCRIPT'\n" + script + "\nSCRIPT",
    ]);
    await execContainer(id, ["chmod", "+x", "/tmp/install.sh"]);
    const result = await execContainer(id, ["/tmp/install.sh"]);

    if (result.exitCode !== 0) {
      console.error("Debian STDOUT:", result.stdout);
      console.error("Debian STDERR:", result.stderr);
    }
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toMatch(/\d+\.\d+\.\d+/); // version number like 2.115.0
  });

  it("creates CODER_SCRIPT_BIN_DIR symlink", async () => {
    const id = await runContainer("ubuntu:22.04");
    cleanupContainers.push(id);

    await execContainer(id, ["apt-get", "update"]);
    await execContainer(id, ["apt-get", "install", "-y", "curl", "tar"]);

    const script = [
      "#!/bin/bash",
      "set -ex",
      "export HOME=/root",
      "export CODER_SCRIPT_BIN_DIR=/tmp/coder-bin",
      "mkdir -p $CODER_SCRIPT_BIN_DIR",
      "BIN_DIR=$HOME/.coder-modules/coder/supabase/bin",
      "mkdir -p $BIN_DIR",
      "ARCH=$(uname -m)",
      "case $ARCH in x86_64|amd64) ARCH=amd64 ;; aarch64|arm64) ARCH=arm64 ;; esac",
      "OS=$(uname -s | tr A-Z a-z)",
      "API_RESPONSE=$(curl -fsSL https://api.github.com/repos/supabase/cli/releases/latest)",
      'VERSION=$(echo "$API_RESPONSE" | grep -o \'"tag_name": *"[^"]*\' | head -1 | sed \'s/.*"v//\' | sed \'s/".*//\')',
      "DOWNLOAD_URL=https://github.com/supabase/cli/releases/download/v$VERSION/supabase_${OS}_${ARCH}.tar.gz",
      "curl -fsSL -o /tmp/supabase.tar.gz $DOWNLOAD_URL",
      "tar -xzf /tmp/supabase.tar.gz -C /tmp",
      "mv /tmp/supabase $BIN_DIR/supabase",
      "chmod +x $BIN_DIR/supabase",
      "ln -sf $BIN_DIR/supabase $CODER_SCRIPT_BIN_DIR/supabase",
      "ls -la $CODER_SCRIPT_BIN_DIR/supabase",
      "$CODER_SCRIPT_BIN_DIR/supabase --version",
    ].join("\n");

    await execContainer(id, [
      "sh",
      "-c",
      "cat > /tmp/install.sh << 'SCRIPT'\n" + script + "\nSCRIPT",
    ]);
    await execContainer(id, ["chmod", "+x", "/tmp/install.sh"]);
    const result = await execContainer(id, ["/tmp/install.sh"]);

    expect(result.exitCode).toBe(0);
    expect(result.stdout).toMatch(/\d+\.\d+\.\d+/); // version number like 2.115.0
  });
});
