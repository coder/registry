#!/bin/bash
set -euo pipefail

if [ -f "$HOME/.bashrc" ]; then
  source "$HOME"/.bashrc
fi

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

    # Ensure binaries are discoverable.
    echo "Creating a symlink for claude"
    sudo ln -s /home/coder/.local/bin/claude /usr/local/bin/claude

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
    while IFS= read -r server_name && IFS= read -r server_json; do
      echo "------------------------"
      echo "Executing: claude mcp add \"$server_name\" '$server_json'"
      claude mcp add "$server_name" "$server_json"
      echo "------------------------"
      echo ""
    done < <(echo "$ARG_MCP" | jq -r '.mcpServers | to_entries[] | .key, (.value | @json)')
  fi

  if [ -n "$ARG_ALLOWED_TOOLS" ]; then
    coder --allowedTools "$ARG_ALLOWED_TOOLS"
  fi

  if [ -n "$ARG_DISALLOWED_TOOLS" ]; then
    coder --disallowedTools "$ARG_DISALLOWED_TOOLS"
  fi

}

function report_tasks() {
  if [ "$ARG_REPORT_TASKS" = "true" ]; then
    echo "Configuring Claude Code to report tasks via Coder MCP..."
    export CODER_MCP_APP_STATUS_SLUG="$ARG_MCP_APP_STATUS_SLUG"
    export CODER_MCP_AI_AGENTAPI_URL="http://localhost:3284"
    coder exp mcp configure claude-code "$ARG_WORKDIR"
  else
    export CODER_MCP_APP_STATUS_SLUG=""
    export CODER_MCP_AI_AGENTAPI_URL=""
    echo "Configuring Claude Code with Coder MCP..."
    coder exp mcp configure claude-code "$ARG_WORKDIR"
  fi
}

install_claude_code_cli
setup_claude_configurations
report_tasks
