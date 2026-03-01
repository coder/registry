#!/bin/bash

set -euo pipefail

BOLD='\033[0;1m'

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

ARG_CLAUDE_CODE_VERSION=${ARG_CLAUDE_CODE_VERSION:-}
ARG_WORKDIR=${ARG_WORKDIR:-"$HOME"}
ARG_INSTALL_CLAUDE_CODE=${ARG_INSTALL_CLAUDE_CODE:-}
ARG_CLAUDE_BINARY_PATH=${ARG_CLAUDE_BINARY_PATH:-"$HOME/.local/bin"}
ARG_CLAUDE_BINARY_PATH="${ARG_CLAUDE_BINARY_PATH/#\~/$HOME}"
ARG_CLAUDE_BINARY_PATH="${ARG_CLAUDE_BINARY_PATH//\$HOME/$HOME}"
ARG_INSTALL_VIA_NPM=${ARG_INSTALL_VIA_NPM:-false}
ARG_REPORT_TASKS=${ARG_REPORT_TASKS:-true}
ARG_MCP_APP_STATUS_SLUG=${ARG_MCP_APP_STATUS_SLUG:-}
ARG_MCP=$(echo -n "${ARG_MCP:-}" | base64 -d)
ARG_MCP_CONFIG_REMOTE_PATH=$(echo -n "${ARG_MCP_CONFIG_REMOTE_PATH:-}" | base64 -d)
ARG_ALLOWED_TOOLS=${ARG_ALLOWED_TOOLS:-}
ARG_DISALLOWED_TOOLS=${ARG_DISALLOWED_TOOLS:-}
ARG_ENABLE_AIBRIDGE=${ARG_ENABLE_AIBRIDGE:-false}

export PATH="$ARG_CLAUDE_BINARY_PATH:$PATH"

echo "--------------------------------"

printf "ARG_CLAUDE_CODE_VERSION: %s\n" "$ARG_CLAUDE_CODE_VERSION"
printf "ARG_WORKDIR: %s\n" "$ARG_WORKDIR"
printf "ARG_INSTALL_CLAUDE_CODE: %s\n" "$ARG_INSTALL_CLAUDE_CODE"
printf "ARG_CLAUDE_BINARY_PATH: %s\n" "$ARG_CLAUDE_BINARY_PATH"
printf "ARG_INSTALL_VIA_NPM: %s\n" "$ARG_INSTALL_VIA_NPM"
printf "ARG_REPORT_TASKS: %s\n" "$ARG_REPORT_TASKS"
printf "ARG_MCP_APP_STATUS_SLUG: %s\n" "$ARG_MCP_APP_STATUS_SLUG"
printf "ARG_MCP: %s\n" "$ARG_MCP"
printf "ARG_MCP_CONFIG_REMOTE_PATH: %s\n" "$ARG_MCP_CONFIG_REMOTE_PATH"
printf "ARG_ALLOWED_TOOLS: %s\n" "$ARG_ALLOWED_TOOLS"
printf "ARG_DISALLOWED_TOOLS: %s\n" "$ARG_DISALLOWED_TOOLS"
printf "ARG_ENABLE_AIBRIDGE: %s\n" "$ARG_ENABLE_AIBRIDGE"

echo "--------------------------------"

function add_mcp_servers() {
  local mcp_json="$1"
  local source_desc="$2"

  while IFS= read -r server_name && IFS= read -r server_json; do
    echo "------------------------"
    echo "Executing: claude mcp add-json \"$server_name\" '$server_json' ($source_desc)"
    claude mcp add-json "$server_name" "$server_json" || echo "Warning: Failed to add MCP server '$server_name', continuing..."
    echo "------------------------"
    echo ""
  done < <(echo "$mcp_json" | jq -r '.mcpServers | to_entries[] | .key, (.value | @json)')
}

function add_path_to_shell_profiles() {
  local path_dir="$1"

  for profile in "$HOME/.profile" "$HOME/.bash_profile" "$HOME/.bashrc" "$HOME/.zprofile" "$HOME/.zshrc"; do
    if [ -f "$profile" ]; then
      if ! grep -q "$path_dir" "$profile" 2> /dev/null; then
        echo "export PATH=\"\$PATH:$path_dir\"" >> "$profile"
        echo "Added $path_dir to $profile"
      fi
    fi
  done

  local fish_config="$HOME/.config/fish/config.fish"
  if [ -f "$fish_config" ]; then
    if ! grep -q "$path_dir" "$fish_config" 2> /dev/null; then
      echo "fish_add_path $path_dir" >> "$fish_config"
      echo "Added $path_dir to $fish_config"
    fi
  fi
}

function ensure_claude_in_path() {
  local CLAUDE_BIN=""
  if command -v claude > /dev/null 2>&1; then
    CLAUDE_BIN=$(command -v claude)
  elif [ -x "$ARG_CLAUDE_BINARY_PATH/claude" ]; then
    CLAUDE_BIN="$ARG_CLAUDE_BINARY_PATH/claude"
  elif [ -x "$HOME/.local/bin/claude" ]; then
    CLAUDE_BIN="$HOME/.local/bin/claude"
  fi

  if [ -z "$CLAUDE_BIN" ] || [ ! -x "$CLAUDE_BIN" ]; then
    echo "Warning: Could not find claude binary"
    return
  fi

  local CLAUDE_DIR
  CLAUDE_DIR=$(dirname "$CLAUDE_BIN")

  if [ -n "${CODER_SCRIPT_BIN_DIR:-}" ] && [ ! -e "$CODER_SCRIPT_BIN_DIR/claude" ]; then
    ln -s "$CLAUDE_BIN" "$CODER_SCRIPT_BIN_DIR/claude"
    echo "Created symlink: $CODER_SCRIPT_BIN_DIR/claude -> $CLAUDE_BIN"
  fi

  add_path_to_shell_profiles "$CLAUDE_DIR"
}

function install_claude_code_cli() {
  if [ "$ARG_INSTALL_CLAUDE_CODE" != "true" ]; then
    echo "Skipping Claude Code installation as per configuration."
    ensure_claude_in_path
    return
  fi

  # Use npm when install_via_npm is true
  if [ "$ARG_INSTALL_VIA_NPM" = "true" ]; then
    echo "WARNING: npm installation method will be deprecated and removed in the next major release."
    echo "Installing Claude Code via npm (version: $ARG_CLAUDE_CODE_VERSION)"
    npm install -g "@anthropic-ai/claude-code@$ARG_CLAUDE_CODE_VERSION"
    echo "Installed Claude Code via npm. Version: $(claude --version || echo 'unknown')"
  else
    echo "Installing Claude Code via official installer"
    set +e
    curl -fsSL claude.ai/install.sh | bash -s -- "$ARG_CLAUDE_CODE_VERSION" 2>&1
    CURL_EXIT=${PIPESTATUS[0]}
    set -e
    if [ $CURL_EXIT -ne 0 ]; then
      echo "Claude Code installer failed with exit code $CURL_EXIT"
    fi
    echo "Installed Claude Code successfully. Version: $(claude --version || echo 'unknown')"
  fi

  ensure_claude_in_path
}

function setup_claude_configurations() {
  if [ ! -d "$ARG_WORKDIR" ]; then
    echo "Warning: The specified folder '$ARG_WORKDIR' does not exist."
    echo "Creating the folder..."
    mkdir -p "$ARG_WORKDIR"
    echo "Folder created successfully."
  fi

  module_path="$HOME/.claude-module"
  mkdir -p "$module_path"

  if [ "$ARG_MCP" != "" ]; then
    (
      cd "$ARG_WORKDIR"
      add_mcp_servers "$ARG_MCP" "in $ARG_WORKDIR"
    )
  fi

  if [ -n "$ARG_MCP_CONFIG_REMOTE_PATH" ] && [ "$ARG_MCP_CONFIG_REMOTE_PATH" != "[]" ]; then
    (
      cd "$ARG_WORKDIR"
      for url in $(echo "$ARG_MCP_CONFIG_REMOTE_PATH" | jq -r '.[]'); do
        echo "Fetching MCP configuration from: $url"
        mcp_json=$(curl -fsSL "$url") || {
          echo "Warning: Failed to fetch MCP configuration from '$url', continuing..."
          continue
        }
        if ! echo "$mcp_json" | jq -e '.mcpServers' > /dev/null 2>&1; then
          echo "Warning: Invalid MCP configuration from '$url' (missing mcpServers), continuing..."
          continue
        fi
        add_mcp_servers "$mcp_json" "from $url"
      done
    )
  fi

  if [ -n "$ARG_ALLOWED_TOOLS" ]; then
    coder --allowedTools "$ARG_ALLOWED_TOOLS"
  fi

  if [ -n "$ARG_DISALLOWED_TOOLS" ]; then
    coder --disallowedTools "$ARG_DISALLOWED_TOOLS"
  fi

}

function configure_standalone_mode() {
  echo "Configuring Claude Code for standalone mode..."

  if [ -z "${CLAUDE_API_KEY:-}" ] \
    && [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ] \
    && [ "${ARG_ENABLE_AIBRIDGE:-false}" = "false" ]; then
    echo "Note: No CLAUDE_API_KEY, no CLAUDE_CODE_OAUTH_TOKEN, and AIBridge disabled — skipping authentication setup"
    return
  fi

  local claude_config="$HOME/.claude.json"
  local workdir_normalized
  workdir_normalized=$(echo "$ARG_WORKDIR" | tr '/' '-')

  # Create or update .claude.json with minimal configuration for API key auth
  # This skips the interactive login prompt and onboarding screens
  if [ -f "$claude_config" ]; then
    echo "Updating existing Claude configuration at $claude_config"

    jq --arg workdir "$ARG_WORKDIR" --arg apikey "${CLAUDE_API_KEY:-}" \
      '.autoUpdaterStatus = "disabled" |
        .bypassPermissionsModeAccepted = true |
        .hasAcknowledgedCostThreshold = true |
        .hasCompletedOnboarding = true |
        .primaryApiKey = $apikey |
        .projects[$workdir].hasCompletedProjectOnboarding = true |
        .projects[$workdir].hasTrustDialogAccepted = true' \
      "$claude_config" > "${claude_config}.tmp" && mv "${claude_config}.tmp" "$claude_config"
  else
    echo "Creating new Claude configuration at $claude_config"
    cat > "$claude_config" << EOF
{
  "autoUpdaterStatus": "disabled",
  "bypassPermissionsModeAccepted": true,
  "hasAcknowledgedCostThreshold": true,
  "hasCompletedOnboarding": true,
  "primaryApiKey": "${CLAUDE_API_KEY:-}",
  "projects": {
    "$ARG_WORKDIR": {
      "hasCompletedProjectOnboarding": true,
      "hasTrustDialogAccepted": true
    }
  }
}
EOF
  fi

  echo "Standalone mode configured successfully"
}

function report_tasks() {
  if [ "$ARG_REPORT_TASKS" = "true" ]; then
    echo "Configuring Claude Code to report tasks via Coder MCP..."
    export CODER_MCP_APP_STATUS_SLUG="$ARG_MCP_APP_STATUS_SLUG"
    export CODER_MCP_AI_AGENTAPI_URL="http://localhost:3284"
    coder exp mcp configure claude-code "$ARG_WORKDIR"
  else
    configure_standalone_mode
  fi
}

install_claude_code_cli
setup_claude_configurations
report_tasks
