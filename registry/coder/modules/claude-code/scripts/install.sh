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
ARG_INSTALL_VIA_NPM=${ARG_INSTALL_VIA_NPM:-false}
ARG_REPORT_TASKS=${ARG_REPORT_TASKS:-true}
ARG_MCP_APP_STATUS_SLUG=${ARG_MCP_APP_STATUS_SLUG:-}
ARG_MCP=$(echo -n "${ARG_MCP:-}" | base64 -d)
ARG_ALLOWED_TOOLS=${ARG_ALLOWED_TOOLS:-}
ARG_DISALLOWED_TOOLS=${ARG_DISALLOWED_TOOLS:-}
ARG_ENABLE_AIBRIDGE=${ARG_ENABLE_AIBRIDGE:-false}

echo "--------------------------------"

printf "ARG_CLAUDE_CODE_VERSION: %s\n" "$ARG_CLAUDE_CODE_VERSION"
printf "ARG_WORKDIR: %s\n" "$ARG_WORKDIR"
printf "ARG_INSTALL_CLAUDE_CODE: %s\n" "$ARG_INSTALL_CLAUDE_CODE"
printf "ARG_CLAUDE_BINARY_PATH: %s\n" "$ARG_CLAUDE_BINARY_PATH"
printf "ARG_INSTALL_VIA_NPM: %s\n" "$ARG_INSTALL_VIA_NPM"
printf "ARG_REPORT_TASKS: %s\n" "$ARG_REPORT_TASKS"
printf "ARG_MCP_APP_STATUS_SLUG: %s\n" "$ARG_MCP_APP_STATUS_SLUG"
printf "ARG_MCP: %s\n" "$ARG_MCP"
printf "ARG_ALLOWED_TOOLS: %s\n" "$ARG_ALLOWED_TOOLS"
printf "ARG_DISALLOWED_TOOLS: %s\n" "$ARG_DISALLOWED_TOOLS"
printf "ARG_ENABLE_AIBRIDGE %s\n" "$ARG_ENABLE_AIBRIDGE"

echo "--------------------------------"

function ensure_claude_in_path() {
  if [ -z "${CODER_SCRIPT_BIN_DIR:-}" ]; then
    echo "CODER_SCRIPT_BIN_DIR not set, skipping PATH setup"
    return
  fi

  if [ ! -e "$CODER_SCRIPT_BIN_DIR/claude" ]; then
    local CLAUDE_BIN=""
    if command -v claude > /dev/null 2>&1; then
      CLAUDE_BIN=$(command -v claude)
    elif [ -x "$ARG_CLAUDE_BINARY_PATH/claude" ]; then
      CLAUDE_BIN="$ARG_CLAUDE_BINARY_PATH/claude"
    elif [ -x "$HOME/.local/bin/claude" ]; then
      CLAUDE_BIN="$HOME/.local/bin/claude"
    fi

    if [ -n "$CLAUDE_BIN" ] && [ -x "$CLAUDE_BIN" ]; then
      ln -s "$CLAUDE_BIN" "$CODER_SCRIPT_BIN_DIR/claude"
      echo "Created symlink: $CODER_SCRIPT_BIN_DIR/claude -> $CLAUDE_BIN"
    else
      echo "Warning: Could not find claude binary to symlink"
    fi
  else
    echo "Claude already available in CODER_SCRIPT_BIN_DIR"
  fi

  local marker="# Added by claude-code module"
  for profile in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
    if [ -f "$profile" ] && ! grep -q "$marker" "$profile" 2> /dev/null; then
      printf "\n%s\nexport PATH=\"%s:\$PATH\"\n" "$marker" "$CODER_SCRIPT_BIN_DIR" >> "$profile"
      echo "Added $CODER_SCRIPT_BIN_DIR to PATH in $profile"
    fi
  done
}

function install_claude_code_cli() {
  if [ "$ARG_INSTALL_CLAUDE_CODE" != "true" ]; then
    echo "Skipping Claude Code installation as per configuration."
    ensure_claude_in_path
    return
  fi

  # Use npm when install_via_npm is true or for specific version pinning
  if [ "$ARG_INSTALL_VIA_NPM" = "true" ] || { [ -n "$ARG_CLAUDE_CODE_VERSION" ] && [ "$ARG_CLAUDE_CODE_VERSION" != "latest" ]; }; then
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
      while IFS= read -r server_name && IFS= read -r server_json; do
        echo "------------------------"
        echo "Executing: claude mcp add-json \"$server_name\" '$server_json' (in $ARG_WORKDIR)"
        claude mcp add-json "$server_name" "$server_json" || echo "Warning: Failed to add MCP server '$server_name', continuing..."
        echo "------------------------"
        echo ""
      done < <(echo "$ARG_MCP" | jq -r '.mcpServers | to_entries[] | .key, (.value | @json)')
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

  if [ -z "${CLAUDE_API_KEY:-}" ] && [ "$ARG_ENABLE_AIBRIDGE" = "false" ]; then
    echo "Note: CLAUDE_API_KEY or enable_aibridge not set, skipping authentication setup"
    return
  fi

  local claude_config="$HOME/.claude.json"
  local workdir_normalized
  workdir_normalized=$(echo "$ARG_WORKDIR" | tr '/' '-')

  # Create or update .claude.json with minimal configuration
  # This skips the interactive login prompt and onboarding screens
  if [ -f "$claude_config" ]; then
    echo "Updating existing Claude configuration at $claude_config"

    jq --arg workdir "$ARG_WORKDIR" \
      '.autoUpdaterStatus = "disabled" |
        .bypassPermissionsModeAccepted = true |
        .hasAcknowledgedCostThreshold = true |
        .hasCompletedOnboarding = true |
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
  "projects": {
    "$ARG_WORKDIR": {
      "hasCompletedProjectOnboarding": true,
      "hasTrustDialogAccepted": true
    }
  }
}
EOF
  fi

  # Add API key only if set
  if [ -n "${CLAUDE_API_KEY:-}" ]; then
    jq --arg apikey "${CLAUDE_API_KEY}" '.primaryApiKey = $apikey' "$claude_config" > "${claude_config}.tmp" && mv "${claude_config}.tmp" "$claude_config"
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
