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

  if ! command_exists copilot; then
    echo "ERROR: Copilot CLI not installed. Run: npm install -g @github/copilot"
    exit 1
  fi

  node_version=$(node --version | sed 's/v//' | cut -d. -f1)
  if [ "$node_version" -lt 22 ]; then
    echo "WARNING: Node.js v$node_version detected. Copilot CLI requires v22+."
  fi
}

check_github_authentication() {
  echo "Checking GitHub authentication via Coder external auth..."

  if command_exists coder; then
    if coder external-auth access-token "${ARG_EXTERNAL_AUTH_ID:-github}" > /dev/null 2>&1; then
      echo "GitHub authentication via Coder external auth: OK"
      return 0
    else
      echo "WARNING: GitHub external auth not configured or expired"
      echo "Please authenticate with GitHub in the Coder UI"
    fi
  fi

  if command_exists gh && gh auth status > /dev/null 2>&1; then
    echo "GitHub CLI authentication detected as fallback"
    return 0
  fi

  echo "WARNING: No GitHub authentication found. Copilot CLI requires:"
  echo "  - GitHub external authentication configured in Coder (recommended)"
  echo "  - Or GitHub CLI with 'gh auth login'"
}

setup_copilot_configurations() {
  mkdir -p "$ARG_WORKDIR"

  local module_path="$HOME/.copilot-module"
  mkdir -p "$module_path"
  mkdir -p "$HOME/.config"

  if [ -n "$ARG_MCP_CONFIG" ]; then
    echo "Configuring custom MCP servers..."
    echo "$ARG_MCP_CONFIG" > "$module_path/mcp_config.json"
  else
    cat > "$module_path/mcp_config.json" << 'EOF'
{
  "mcpServers": {
    "github": {
      "command": "@github/copilot-mcp-github"
    }
  }
}
EOF
  fi

  setup_copilot_config

  echo "$ARG_WORKDIR" > "$module_path/trusted_directories"
}

setup_copilot_config() {
  local config_file="$HOME/.config/copilot.json"

  if [ -n "$ARG_COPILOT_CONFIG" ]; then
    echo "Setting up Copilot configuration..."
    echo "$ARG_COPILOT_CONFIG" > "$config_file"
  else
    echo "ERROR: No Copilot configuration provided"
    exit 1
  fi
}

configure_coder_integration() {
  if [ "$ARG_REPORT_TASKS" = "true" ]; then
    echo "Configuring Copilot CLI task reporting..."
    export CODER_MCP_APP_STATUS_SLUG="$ARG_MCP_APP_STATUS_SLUG"
    export CODER_MCP_AI_AGENTAPI_URL="http://localhost:3284"

    if command_exists coder; then
      coder exp mcp configure copilot-cli "$ARG_WORKDIR" 2> /dev/null || true
    fi
  else
    echo "Task reporting disabled."
  fi
}

validate_prerequisites
check_github_authentication
setup_copilot_configurations
configure_coder_integration

echo "Copilot CLI module setup completed."
