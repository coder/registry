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
  local config_file="$HOME/.config/copilot.json"

  if [ -n "$ARG_COPILOT_CONFIG" ]; then
    echo "Setting up Copilot configuration with MCP servers..."
    
    if [ -n "$ARG_MCP_CONFIG" ]; then
      echo "Merging custom MCP servers into Copilot configuration..."
      if command_exists jq; then
        local merged_config
        merged_config=$(echo "$ARG_COPILOT_CONFIG" | jq --argjson mcp_config "$ARG_MCP_CONFIG" '
          . + {
            mcpServers: ($mcp_config.mcpServers // {}) |
            if .github == null then
              .github = {"command": "@github/copilot-mcp-github"}
            else . end |
            if "'"$ARG_REPORT_TASKS"'" == "true" then
              .coder = {
                "command": "coder",
                "args": ["exp", "mcp", "server"],
                "type": "stdio",
                "env": {
                  "CODER_MCP_APP_STATUS_SLUG": "'"$ARG_MCP_APP_STATUS_SLUG"'",
                  "CODER_MCP_AI_AGENTAPI_URL": "http://localhost:3284"
                }
              }
            else . end
          }
        ')
        echo "$merged_config" > "$config_file"
      elif command_exists node; then
        node -e "
          const copilotConfig = JSON.parse(\`$ARG_COPILOT_CONFIG\`);
          const mcpConfig = JSON.parse(\`$ARG_MCP_CONFIG\`);
          
          copilotConfig.mcpServers = mcpConfig.mcpServers || {};
          
          if (!copilotConfig.mcpServers.github) {
            copilotConfig.mcpServers.github = {
              command: '@github/copilot-mcp-github'
            };
          }
          
          if ('$ARG_REPORT_TASKS' === 'true') {
            copilotConfig.mcpServers.coder = {
              command: 'coder',
              args: ['exp', 'mcp', 'server'],
              type: 'stdio',
              env: {
                CODER_MCP_APP_STATUS_SLUG: '$ARG_MCP_APP_STATUS_SLUG',
                CODER_MCP_AI_AGENTAPI_URL: 'http://localhost:3284'
              }
            };
          }
          
          console.log(JSON.stringify(copilotConfig, null, 2));
        " > "$config_file"
      else
        echo "$ARG_COPILOT_CONFIG" > "$config_file"
      fi
    else
      if [ "$ARG_REPORT_TASKS" = "true" ]; then
        echo "Adding default MCP servers with Coder task reporting..."
        if command_exists jq; then
          echo "$ARG_COPILOT_CONFIG" | jq '. + {
            mcpServers: {
              "github": {
                "command": "@github/copilot-mcp-github"
              },
              "coder": {
                "command": "coder",
                "args": ["exp", "mcp", "server"],
                "type": "stdio",
                "env": {
                  "CODER_MCP_APP_STATUS_SLUG": "'"$ARG_MCP_APP_STATUS_SLUG"'",
                  "CODER_MCP_AI_AGENTAPI_URL": "http://localhost:3284"
                }
              }
            }
          }' > "$config_file"
        elif command_exists node; then
          node -e "
            const config = JSON.parse(\`$ARG_COPILOT_CONFIG\`);
            config.mcpServers = {
              github: { command: '@github/copilot-mcp-github' },
              coder: {
                command: 'coder',
                args: ['exp', 'mcp', 'server'],
                type: 'stdio',
                env: {
                  CODER_MCP_APP_STATUS_SLUG: '$ARG_MCP_APP_STATUS_SLUG',
                  CODER_MCP_AI_AGENTAPI_URL: 'http://localhost:3284'
                }
              }
            };
            console.log(JSON.stringify(config, null, 2));
          " > "$config_file"
        else
          echo "$ARG_COPILOT_CONFIG" > "$config_file"
        fi
      else
        echo "Adding default GitHub MCP server..."
        if command_exists jq; then
          echo "$ARG_COPILOT_CONFIG" | jq '. + {
            mcpServers: {
              "github": {
                "command": "@github/copilot-mcp-github"
              }
            }
          }' > "$config_file"
        elif command_exists node; then
          node -e "
            const config = JSON.parse(\`$ARG_COPILOT_CONFIG\`);
            config.mcpServers = { github: { command: '@github/copilot-mcp-github' } };
            console.log(JSON.stringify(config, null, 2));
          " > "$config_file"
        else
          echo "$ARG_COPILOT_CONFIG" > "$config_file"
        fi
      fi
    fi
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
install_copilot_cli
check_github_authentication
setup_copilot_configurations
configure_coder_integration

echo "Copilot CLI module setup completed."
