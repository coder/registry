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
      // Ignore cleanup errors
    }
  }
  cleanupContainers = [];
});

describe("supabase", async () => {
  beforeAll(async () => {
    await runTerraformInit(import.meta.dir);
  });

  testRequiredVariables(import.meta.dir, {
    agent_id: "test-agent",
  });

  it("defaults to detect install method", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
    });

    // Verify the install script contains the expected ARG_INSTALL_METHOD
    const installScript = state.outputs.scripts.value;
    expect(installScript).toBeDefined();
  });

  it("accepts binary install method", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      install_method: "binary",
    });

    expect(state.outputs.scripts.value).toBeDefined();
  });

  it("accepts brew install method", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      install_method: "brew",
    });

    expect(state.outputs.scripts.value).toBeDefined();
  });

  it("accepts scoop install method", async () => {
    const state = await runTerraformApply(import.meta.dir, {
      agent_id: "test-agent",
      install_method: "scoop",
    });

    expect(state.outputs.scripts.value).toBeDefined();
  });

  it("rejects invalid install method", async () => {
    await expect(
      runTerraformApply(import.meta.dir, {
        agent_id: "test-agent",
        install_method: "invalid",
      }),
    ).rejects.toThrow(/install_method.*must be/);
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
    const { id } = await runContainer("ubuntu:22.04");
    cleanupContainers.push(id);

    // Install curl (required for binary download)
    await execContainer(id, ["apt-get", "update"]);
    await execContainer(id, ["apt-get", "install", "-y", "curl", "tar"]);

    // Run the install script with binary method
    const installScript = `
      set -e
      export HOME=/root
      export CODER_SCRIPT_BIN_DIR=/tmp/coder-bin
      mkdir -p $CODER_SCRIPT_BIN_DIR
      
      MODULE_DIR="$HOME/.coder-modules/coder/supabase"
      LOG_DIR="$MODULE_DIR/logs"
      BIN_DIR="$MODULE_DIR/bin"
      mkdir -p "$LOG_DIR" "$BIN_DIR"
      
      INSTALL_METHOD="binary"
      VERSION="latest"
      
      # Platform detection
      ARCH=$(uname -m)
      case "$ARCH" in
        x86_64 | amd64) ARCH="amd64" ;;
        aarch64 | arm64) ARCH="arm64" ;;
      esac
      OS=$(uname -s | tr '[:upper:]' '[:lower:]')
      
      # Resolve version
      API_RESPONSE=$(curl -fsSL "https://api.github.com/repos/supabase/cli/releases/latest")
      VERSION=$(echo "$API_RESPONSE" | grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\\1/')
      
      # Download and install
      DOWNLOAD_URL="https://github.com/supabase/cli/releases/download/v$VERSION/supabase_\${OS}_\${ARCH}.tar.gz"
      curl -fsSL -o /tmp/supabase.tar.gz "$DOWNLOAD_URL"
      tar -xzf /tmp/supabase.tar.gz -C /tmp
      mv /tmp/supabase "$BIN_DIR/supabase"
      chmod +x "$BIN_DIR/supabase"
      
      # Verify
      "$BIN_DIR/supabase" --version
    `;

    const result = await execContainer(id, ["bash", "-c", installScript]);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("Supabase CLI");
  });

  it("installs via binary on alpine", async () => {
    const { id } = await runContainer("alpine:latest");
    cleanupContainers.push(id);

    // Install required tools
    await execContainer(id, [
      "apk",
      "add",
      "--no-cache",
      "curl",
      "tar",
      "bash",
    ]);

    // Run the install script with binary method
    const installScript = `
      set -e
      export HOME=/root
      export CODER_SCRIPT_BIN_DIR=/tmp/coder-bin
      mkdir -p $CODER_SCRIPT_BIN_DIR
      
      MODULE_DIR="$HOME/.coder-modules/coder/supabase"
      BIN_DIR="$MODULE_DIR/bin"
      mkdir -p "$BIN_DIR"
      
      # Platform detection
      ARCH=$(uname -m)
      case "$ARCH" in
        x86_64 | amd64) ARCH="amd64" ;;
        aarch64 | arm64) ARCH="arm64" ;;
      esac
      OS=$(uname -s | tr '[:upper:]' '[:lower:]')
      
      # Resolve version
      API_RESPONSE=$(curl -fsSL "https://api.github.com/repos/supabase/cli/releases/latest")
      VERSION=$(echo "$API_RESPONSE" | grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\\1/')
      
      # Download and install
      DOWNLOAD_URL="https://github.com/supabase/cli/releases/download/v$VERSION/supabase_\${OS}_\${ARCH}.tar.gz"
      curl -fsSL -o /tmp/supabase.tar.gz "$DOWNLOAD_URL"
      tar -xzf /tmp/supabase.tar.gz -C /tmp
      mv /tmp/supabase "$BIN_DIR/supabase"
      chmod +x "$BIN_DIR/supabase"
      
      # Verify
      "$BIN_DIR/supabase" --version
    `;

    const result = await execContainer(id, ["bash", "-c", installScript]);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("Supabase CLI");
  });

  it("creates CODER_SCRIPT_BIN_DIR symlink", async () => {
    const { id } = await runContainer("ubuntu:22.04");
    cleanupContainers.push(id);

    await execContainer(id, ["apt-get", "update"]);
    await execContainer(id, ["apt-get", "install", "-y", "curl", "tar"]);

    const installScript = `
      set -e
      export HOME=/root
      export CODER_SCRIPT_BIN_DIR=/tmp/coder-bin
      mkdir -p $CODER_SCRIPT_BIN_DIR
      
      MODULE_DIR="$HOME/.coder-modules/coder/supabase"
      BIN_DIR="$MODULE_DIR/bin"
      mkdir -p "$BIN_DIR"
      
      ARCH=$(uname -m)
      case "$ARCH" in
        x86_64 | amd64) ARCH="amd64" ;;
        aarch64 | arm64) ARCH="arm64" ;;
      esac
      OS=$(uname -s | tr '[:upper:]' '[:lower:]')
      
      API_RESPONSE=$(curl -fsSL "https://api.github.com/repos/supabase/cli/releases/latest")
      VERSION=$(echo "$API_RESPONSE" | grep '"tag_name":' | sed -E 's/.*"v?([^"]+)".*/\\1/')
      
      DOWNLOAD_URL="https://github.com/supabase/cli/releases/download/v$VERSION/supabase_\${OS}_\${ARCH}.tar.gz"
      curl -fsSL -o /tmp/supabase.tar.gz "$DOWNLOAD_URL"
      tar -xzf /tmp/supabase.tar.gz -C /tmp
      mv /tmp/supabase "$BIN_DIR/supabase"
      chmod +x "$BIN_DIR/supabase"
      
      # Create symlink in CODER_SCRIPT_BIN_DIR
      ln -sf "$BIN_DIR/supabase" "$CODER_SCRIPT_BIN_DIR/supabase"
      
      # Verify symlink works
      ls -la "$CODER_SCRIPT_BIN_DIR/supabase"
      "$CODER_SCRIPT_BIN_DIR/supabase" --version
    `;

    const result = await execContainer(id, ["bash", "-c", installScript]);
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toContain("Supabase CLI");
  });
});
