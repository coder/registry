#!/bin/bash
# Install script for kiro-cli module

set -o errexit
set -o pipefail

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

# Inputs
ARG_INSTALL=${ARG_INSTALL:-true}
ARG_VERSION=${ARG_VERSION:-latest}
ARG_KIRO_INSTALL_URL=${ARG_KIRO_INSTALL_URL:-https://desktop-release.q.us-east-1.amazonaws.com}
ARG_AUTH_TARBALL=${ARG_AUTH_TARBALL:-}
ARG_AGENT_CONFIG=${ARG_AGENT_CONFIG:-}
ARG_AGENT_NAME=${ARG_AGENT_NAME:-default-agent}
ARG_MODULE_DIR_NAME=${ARG_MODULE_DIR_NAME:-.kiro}
ARG_CODER_MCP_APP_STATUS_SLUG=${ARG_CODER_MCP_APP_STATUS_SLUG:-}
ARG_CODER_MCP_INSTRUCTIONS=${ARG_CODER_MCP_INSTRUCTIONS:-}
ARG_REPORT_TASKS=${ARG_REPORT_TASKS:-true}

mkdir -p "$HOME/$ARG_MODULE_DIR_NAME"

# Decode base64 inputs
ARG_AGENT_CONFIG_DECODED=""
if [ -n "$ARG_AGENT_CONFIG" ]; then
  ARG_AGENT_CONFIG_DECODED=$(echo -n "$ARG_AGENT_CONFIG" | base64 -d)
fi

ARG_CODER_MCP_INSTRUCTIONS_DECODED=""
if [ -n "$ARG_CODER_MCP_INSTRUCTIONS" ]; then
  ARG_CODER_MCP_INSTRUCTIONS_DECODED=$(echo -n "$ARG_CODER_MCP_INSTRUCTIONS" | base64 -d)
fi

echo "--------------------------------"
echo "install: $ARG_INSTALL"
echo "version: $ARG_VERSION"
echo "kiro_install_url: $ARG_KIRO_INSTALL_URL"
echo "agent_name: $ARG_AGENT_NAME"
echo "coder_mcp_app_status_slug: $ARG_CODER_MCP_APP_STATUS_SLUG"
echo "module_dir_name: $ARG_MODULE_DIR_NAME"
echo "auth_tarball_provided: ${ARG_AUTH_TARBALL}"
echo "report_tasks: ${ARG_REPORT_TASKS}"
echo "--------------------------------"

# Install Kiro CLI if requested
function install_kiro_cli() {
  if [ "$ARG_INSTALL" = "true" ]; then
    echo "Installing Kiro CLI..."
    PREV_DIR="$PWD"
    TMP_DIR="$(mktemp -d)"
    cd "$TMP_DIR"

    ARCH="$(uname -m)"
    case "$ARCH" in
      "x86_64")
        KIRO_URL="${ARG_KIRO_INSTALL_URL}/${ARG_VERSION}/kirocli-x86_64-linux.zip"
        ;;
      "aarch64" | "arm64")
        KIRO_URL="${ARG_KIRO_INSTALL_URL}/${ARG_VERSION}/kirocli-aarch64-linux.zip"
        ;;
      *)
        echo "Error: Unsupported architecture: $ARCH. Kiro CLI only supports x86_64 and arm64."
        exit 1
        ;;
    esac

    echo "Downloading Kiro CLI for $ARCH from $KIRO_URL..."
    curl --proto '=https' --tlsv1.2 -sSf "$KIRO_URL" -o "kirocli.zip"
    unzip kirocli.zip
    ./kirocli/install.sh --no-confirm
    cd "$PREV_DIR"
    rm -rf "$TMP_DIR"

    # Ensure binaries are discoverable; create stable symlink to kiro-cli
    CANDIDATES=(
      "$(command -v kiro-cli || true)"
      "$HOME/.local/bin/kiro-cli"
    )
    FOUND_BIN=""
    for c in "${CANDIDATES[@]}"; do
      if [ -n "$c" ] && [ -x "$c" ]; then
        FOUND_BIN="$c"
        break
      fi
    done
    export PATH="$PATH:$HOME/.local/bin"
    echo "Installed Kiro CLI at: $(command -v kiro-cli || true) (resolved: $FOUND_BIN)"
  fi
}

# Extract authentication tarball
function extract_auth_tarball() {
  if [ -n "$ARG_AUTH_TARBALL" ]; then
    echo "Extracting auth tarball..."

    if ! command_exists zstd; then
      echo "Error: zstd is required to extract the authentication tarball but is not installed."
      echo "Please install zstd using the pre_install_script parameter."
      exit 1
    fi

    PREV_DIR="$PWD"
    echo "$ARG_AUTH_TARBALL" | base64 -d > /tmp/auth.tar.zst
    rm -rf ~/.local/share/kiro-cli
    mkdir -p ~/.local/share/kiro-cli
    cd ~/.local/share/kiro-cli
    tar -I zstd -xf /tmp/auth.tar.zst
    rm /tmp/auth.tar.zst
    cd "$PREV_DIR"
    echo "Extracted auth tarball to ~/.local/share/kiro-cli"
  else
    echo "Warning: No auth tarball provided. Kiro CLI may require manual authentication."
  fi
}

# Configure MCP integration and create agent
function configure_agent() {
  # Create Kiro CLI agent configuration directory
  AGENT_CONFIG_DIR="$HOME/.kiro/agents"
  mkdir -p "$AGENT_CONFIG_DIR"
  ALLOWED_TOOLS="coder_get_workspace\,coder_create_workspace\,coder_list_workspaces\,coder_list_templates\,coder_template_version_parameters\,coder_get_authenticated_user\,coder_create_workspace_build\,coder_create_template_version\,coder_get_workspace_agent_logs\,coder_get_workspace_build_logs\,coder_get_template_version_logs\,coder_update_template_active_version\,coder_upload_tar_file\,coder_create_template\,coder_delete_template\,coder_workspace_bash"
  if [ -n "$ARG_AGENT_CONFIG_DECODED" ]; then
    echo "Applying custom MCP configuration..."
    # Use agent name as filename for the configuration
    echo "$ARG_AGENT_CONFIG_DECODED" > "$AGENT_CONFIG_DIR/${ARG_AGENT_NAME}.json"
    echo "Custom configuration saved to $AGENT_CONFIG_DIR/${ARG_AGENT_NAME}.json"
  fi
  if [ "$ARG_REPORT_TASKS" = "true" ]; then
    echo "Configuring Kiro CLI to report tasks via Coder MCP..."
    kiro-cli mcp add --name coder \
      --command "coder" \
      --agent "$ARG_AGENT_NAME" \
      --args "exp,mcp,server,--allowed-tools,coder_report_task,--instructions,'$ARG_CODER_MCP_INSTRUCTIONS_DECODED'" \
      --env "CODER_MCP_APP_STATUS_SLUG=${ARG_CODER_MCP_APP_STATUS_SLUG}" \
      --env "CODER_MCP_AI_AGENTAPI_URL=http://localhost:3284" \
      --env "CODER_AGENT_URL=${CODER_AGENT_URL}" \
      --env "CODER_AGENT_TOKEN=${CODER_AGENT_TOKEN}" \
      --force || echo "Warning: Failed to add Coder MCP server"
  else
    kiro-cli mcp add --name coder \
      --command "coder" \
      --agent "$ARG_AGENT_NAME" \
      --args "exp,mcp,server,--allowed-tools,coder_report_task" \
      --env "CODER_AGENT_URL=${CODER_AGENT_URL}" \
      --env "CODER_AGENT_TOKEN=${CODER_AGENT_TOKEN}" \
      --force || echo "Warning: Failed to add Coder MCP server"
  fi
  echo "Added Coder MCP server into $ARG_AGENT_NAME in Kiro CLI configuration"
  kiro-cli settings chat.defaultAgent "$ARG_AGENT_NAME"
}

# Main execution
install_kiro_cli
extract_auth_tarball
configure_agent

echo "Kiro CLI installation and configuration complete!"
