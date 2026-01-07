#!/bin/bash

set -euo pipefail
set -x

BOLD='\033[0;1m'

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

ARG_CLAUDE_CODE_VERSION=${ARG_CLAUDE_CODE_VERSION:-}
ARG_WORKDIR=${ARG_WORKDIR:-"$HOME"}
ARG_INSTALL_CLAUDE_CODE=${ARG_INSTALL_CLAUDE_CODE:-}
ARG_REPORT_TASKS=${ARG_REPORT_TASKS:-true}
ARG_MCP_APP_STATUS_SLUG=${ARG_MCP_APP_STATUS_SLUG:-}
ARG_MCP=$(echo -n "${ARG_MCP:-}" | base64 -d)
ARG_ALLOWED_TOOLS=${ARG_ALLOWED_TOOLS:-}
ARG_DISALLOWED_TOOLS=${ARG_DISALLOWED_TOOLS:-}

echo "--------------------------------"

printf "ARG_CLAUDE_CODE_VERSION: %s\n" "$ARG_CLAUDE_CODE_VERSION"
printf "ARG_WORKDIR: %s\n" "$ARG_WORKDIR"
printf "ARG_INSTALL_CLAUDE_CODE: %s\n" "$ARG_INSTALL_CLAUDE_CODE"
printf "ARG_REPORT_TASKS: %s\n" "$ARG_REPORT_TASKS"
printf "ARG_MCP_APP_STATUS_SLUG: %s\n" "$ARG_MCP_APP_STATUS_SLUG"
printf "ARG_MCP: %s\n" "$ARG_MCP"
printf "ARG_ALLOWED_TOOLS: %s\n" "$ARG_ALLOWED_TOOLS"
printf "ARG_DISALLOWED_TOOLS: %s\n" "$ARG_DISALLOWED_TOOLS"

echo "--------------------------------"

function install_claude_code_cli() {
  if [ "$ARG_INSTALL_CLAUDE_CODE" = "true" ]; then
    echo "Installing Claude Code via official installer"
    set +e
    curl -fsSL claude.ai/install.sh | bash -s -- "$ARG_CLAUDE_CODE_VERSION" 2>&1
    CURL_EXIT=${PIPESTATUS[0]}
    set -e
    if [ $CURL_EXIT -ne 0 ]; then
      echo "Claude Code installer failed with exit code $$CURL_EXIT"
    fi
    echo "Installed Claude Code successfully. Version: $(claude --version || echo 'unknown')"
  else
    echo "Skipping Claude Code installation as per configuration."
  fi
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
        claude mcp add-json "$server_name" "$server_json"
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

  if [ -z "${CLAUDE_API_KEY:-}" ]; then
    echo "Note: CLAUDE_API_KEY not set, skipping authentication setup"
    return
  fi

  local claude_config="$HOME/.claude.json"
  local workdir_normalized
  workdir_normalized=$(echo "$ARG_WORKDIR" | tr '/' '-')

  # Create or update .claude.json with minimal configuration for API key auth
  # This skips the interactive login prompt and onboarding screens
  if [ -f "$claude_config" ]; then
    echo "Updating existing Claude configuration at $claude_config"

    jq --arg apikey "${CLAUDE_API_KEY:-}" \
      --arg workdir "$ARG_WORKDIR" \
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
