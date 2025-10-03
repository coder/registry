#!/bin/bash
set -euo pipefail

source "$HOME"/.bashrc

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

ARG_WORKDIR=${ARG_WORKDIR:-"$HOME"}
ARG_REPORT_TASKS=${ARG_REPORT_TASKS:-true}
ARG_MCP_APP_STATUS_SLUG=${ARG_MCP_APP_STATUS_SLUG:-}
ARG_MCP_CONFIG=$(echo -n "${ARG_MCP_CONFIG:-}" | base64 -d 2> /dev/null || echo "")
ARG_COPILOT_CONFIG=$(echo -n "${ARG_COPILOT_CONFIG:-}" | base64 -d 2> /dev/null || echo "")
ARG_EXTERNAL_AUTH_ID=${ARG_EXTERNAL_AUTH_ID:-github}

validate_prerequisites() {
  if ! command_exists node; then
    echo "ERROR: Node.js not found. Copilot CLI requires Node.js v22+."
    echo "Install with: curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt-get install -y nodejs"
    exit 1
  fi

  if ! command_exists npm; then
    echo "ERROR: npm not found. Copilot CLI requires npm v10+."
    exit 1
  fi

  node_version=$(node --version | sed 's/v//' | cut -d. -f1)
  if [ "$node_version" -lt 22 ]; then
    echo "WARNING: Node.js v$node_version detected. Copilot CLI requires v22+."
  fi
}

install_copilot_cli() {
  if ! command_exists copilot; then
    echo "Installing GitHub Copilot CLI..."
    npm install -g @github/copilot

    if ! command_exists copilot; then
      echo "ERROR: Failed to install Copilot CLI"
      exit 1
    fi

    echo "GitHub Copilot CLI installed successfully"
  else
    echo "GitHub Copilot CLI already installed"
  fi
}

check_github_authentication() {
  echo "Checking GitHub authentication..."

  if [ -n "$GITHUB_TOKEN" ]; then
    echo "✓ GitHub token provided via module configuration"
    return 0
  fi

  if command_exists coder; then
    if coder external-auth access-token "${ARG_EXTERNAL_AUTH_ID:-github}" > /dev/null 2>&1; then
      echo "✓ GitHub OAuth authentication via Coder external auth"
      return 0
    fi
  fi

  if command_exists gh && gh auth status > /dev/null 2>&1; then
    echo "✓ GitHub OAuth authentication via GitHub CLI"
    return 0
  fi

  echo "⚠ No GitHub authentication detected"
  echo "  Copilot CLI will prompt for authentication when started"
  echo "  For seamless experience, configure GitHub external auth in Coder or run 'gh auth login'"
  return 0
}

setup_copilot_configurations() {
  mkdir -p "$ARG_WORKDIR"

  local module_path="$HOME/.copilot-module"
  mkdir -p "$module_path"
  mkdir -p "$HOME/.config"

  setup_copilot_config

  echo "$ARG_WORKDIR" > "$module_path/trusted_directories"
}

setup_copilot_config() {
  local copilot_config_dir="$HOME/.copilot"
  local copilot_config_file="$copilot_config_dir/config.json"
  local mcp_config_file="$copilot_config_dir/mcp-config.json"

  mkdir -p "$copilot_config_dir"

  if [ -n "$ARG_COPILOT_CONFIG" ]; then
    echo "Setting up Copilot CLI configuration..."

    if command_exists jq; then
      echo "$ARG_COPILOT_CONFIG" | jq 'del(.mcpServers)' > "$copilot_config_file"
    else
      echo "$ARG_COPILOT_CONFIG" > "$copilot_config_file"
    fi

    echo "Setting up MCP server configuration..."
    setup_mcp_config "$mcp_config_file"
  else
    echo "ERROR: No Copilot configuration provided"
    exit 1
  fi
}

setup_mcp_config() {
  local mcp_config_file="$1"

  echo '{"mcpServers": {}}' > "$mcp_config_file"

  if [ "$ARG_REPORT_TASKS" = "true" ] && [ -n "$ARG_MCP_APP_STATUS_SLUG" ]; then
    echo "Adding Coder MCP server for task reporting..."
    setup_coder_mcp_server "$mcp_config_file"
  fi

  if [ -n "$ARG_MCP_CONFIG" ]; then
    echo "Adding custom MCP servers..."
    add_custom_mcp_servers "$mcp_config_file"
  fi

  echo "MCP configuration completed: $mcp_config_file"
}

setup_coder_mcp_server() {
  local mcp_config_file="$1"

  local coder_mcp_wrapper_script
  coder_mcp_wrapper_script=$(
    cat << EOF
#!/usr/bin/env bash
set -e

export CODER_MCP_APP_STATUS_SLUG="${ARG_MCP_APP_STATUS_SLUG}"
export CODER_MCP_AI_AGENTAPI_URL="http://localhost:3284"
export CODER_AGENT_URL="${CODER_AGENT_URL}"
export CODER_AGENT_TOKEN="${CODER_AGENT_TOKEN}"

exec coder exp mcp server
EOF
  )
  echo "$coder_mcp_wrapper_script" > "/tmp/coder-mcp-server.sh"
  chmod +x /tmp/coder-mcp-server.sh

  local coder_mcp_config
  coder_mcp_config=$(
    cat << EOF
{
  "mcpServers": {
    "coder": {
      "command": "/tmp/coder-mcp-server.sh",
      "args": [],
      "description": "Report ALL tasks and statuses (in progress, done, failed) you are working on.",
      "name": "Coder",
      "timeout": 3000,
      "type": "local",
      "tools": ["*"],
      "trust": true
    }
  }
}
EOF
  )

  echo "$coder_mcp_config" > "$mcp_config_file"
}

add_custom_mcp_servers() {
  local mcp_config_file="$1"

  if command_exists jq; then
    local custom_servers
    custom_servers=$(echo "$ARG_MCP_CONFIG" | jq '.mcpServers // {}')

    local updated_config
    updated_config=$(jq --argjson custom "$custom_servers" '.mcpServers += $custom' "$mcp_config_file")
    echo "$updated_config" > "$mcp_config_file"
  elif command_exists node; then
    node -e "
      const fs = require('fs');
      const existing = JSON.parse(fs.readFileSync('$mcp_config_file', 'utf8'));
      const input = JSON.parse(\`$ARG_MCP_CONFIG\`);
      const custom = input.mcpServers || {};
      existing.mcpServers = {...existing.mcpServers, ...custom};
      fs.writeFileSync('$mcp_config_file', JSON.stringify(existing, null, 2));
    "
  else
    echo "WARNING: jq and node not available, cannot merge custom MCP servers"
  fi
}

configure_copilot_model() {
  if [ -n "$ARG_COPILOT_MODEL" ] && [ "$ARG_COPILOT_MODEL" != "claude-sonnet-4.5" ]; then
    echo "Setting Copilot CLI model to: $ARG_COPILOT_MODEL"
    copilot config model "$ARG_COPILOT_MODEL" || {
      echo "WARNING: Failed to set model via copilot config, will use environment variable fallback"
      export COPILOT_MODEL="$ARG_COPILOT_MODEL"
    }
  fi
}

configure_coder_integration() {
  if [ "$ARG_REPORT_TASKS" = "true" ] && [ -n "$ARG_MCP_APP_STATUS_SLUG" ]; then
    echo "Configuring Copilot CLI task reporting..."
    export CODER_MCP_APP_STATUS_SLUG="$ARG_MCP_APP_STATUS_SLUG"
    export CODER_MCP_AI_AGENTAPI_URL="http://localhost:3284"
    echo "✓ Coder MCP server configured for task reporting"
  else
    echo "Task reporting disabled or no app status slug provided."
    export CODER_MCP_APP_STATUS_SLUG=""
    export CODER_MCP_AI_AGENTAPI_URL=""
  fi
}

validate_prerequisites
install_copilot_cli
check_github_authentication
setup_copilot_configurations
configure_copilot_model
configure_coder_integration

echo "Copilot CLI module setup completed."
