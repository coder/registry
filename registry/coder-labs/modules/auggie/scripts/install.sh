#!/bin/bash
set -euo pipefail

source "$HOME"/.bashrc

BOLD='\033[0;1m'

# Function to check if a command exists
command_exists() {
  command -v "$1" > /dev/null 2>&1
}

ARG_AUGGIE_INSTALL=${ARG_AUGGIE_INSTALL:-true}
ARG_AUGGIE_VERSION=${ARG_AUGGIE_VERSION:-}
ARG_MCP_APP_STATUS_SLUG=${ARG_MCP_APP_STATUS_SLUG:-}
ARG_AUGGIE_RULES=$(echo -n "${ARG_AUGGIE_RULES:-}" | base64 -d)
ARG_MCP_CONFIG=${ARG_MCP_CONFIG:-}

echo "--------------------------------"

printf "install auggie: %s\n" "$ARG_AUGGIE_INSTALL"
printf "auggie_version: %s\n" "$ARG_AUGGIE_VERSION"
printf "app_slug: %s\n" "$ARG_MCP_APP_STATUS_SLUG"
printf "rules: %s\n" "$ARG_AUGGIE_RULES"

echo "--------------------------------"


function check_dependencies() {
  if ! command_exists node; then
    printf "Error: Node.js is not installed. Please install Node.js manually or use the pre_install_script to install it.\n"
    exit 1
  fi

  if ! command_exists npm; then
    printf "Error: npm is not installed. Please install npm manually or use the pre_install_script to install it.\n"
    exit 1
  fi

  printf "Node.js version: %s\n" "$(node --version)"
  printf "npm version: %s\n" "$(npm --version)"
}

function install_auggie() {
  if [ "${ARG_AUGGIE_INSTALL}" = "true" ]; then
    check_dependencies

    printf "%s Installing Auggie CLI\n" "${BOLD}"

    NPM_GLOBAL_PREFIX="${HOME}/.npm-global"
    if [ ! -d "$NPM_GLOBAL_PREFIX" ]; then
      mkdir -p "$NPM_GLOBAL_PREFIX"
    fi
    
    npm config set prefix "$NPM_GLOBAL_PREFIX"
    
    export PATH="$NPM_GLOBAL_PREFIX/bin:$PATH"
    
    if [ -n "$ARG_AUGGIE_VERSION" ]; then
      npm install -g "@augmentcode/auggie@$ARG_AUGGIE_VERSION"
    else
      npm install -g "@augmentcode/auggie"
    fi
    
    if ! grep -q "export PATH=\"\$HOME/.npm-global/bin:\$PATH\"" "$HOME/.bashrc"; then
      echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.bashrc"
    fi
    
    printf "%s Successfully installed Auggie CLI. Version: %s\n" "${BOLD}" "$(auggie --version)"
  else
    printf "Skipping Auggie CLI installation (install_auggie=false)\n"
  fi
}


function create_coder_mcp() {
  AUGGIE_CODER_MCP_FILE="$HOME/.augment/coder_mcp.json"
  CODER_MCP=$(
    cat << EOF
{
  "mcpServers":{
   "coder": {
     "args": ["exp", "mcp", "server"],
     "command": "coder",
     "env": {
       "CODER_MCP_APP_STATUS_SLUG": "${ARG_MCP_APP_STATUS_SLUG}",
       "CODER_MCP_AI_AGENTAPI_URL": "http://localhost:3284",
       "CODER_AGENT_URL": "${CODER_AGENT_URL:-}",
       "CODER_AGENT_TOKEN": "${CODER_AGENT_TOKEN:-}"
     }
   }
  }
}
EOF
  )
  mkdir -p "$(dirname "$AUGGIE_CODER_MCP_FILE")"
  echo "$CODER_MCP" > "$AUGGIE_CODER_MCP_FILE"
  printf "Coder MCP config created at: %s\n" "$AUGGIE_CODER_MCP_FILE"
}

function create_user_mcp() {
  if [ -n "$ARG_MCP_CONFIG" ]; then
    USER_MCP_CONFIG_FILE="$HOME/.augment/user_mcp.json"
    USER_MCP_CONTENT=$(echo -n "$ARG_MCP_CONFIG" | base64 -d)
    mkdir -p "$(dirname "$USER_MCP_CONFIG_FILE")"
    echo "$USER_MCP_CONTENT" > "$USER_MCP_CONFIG_FILE"
    printf "User MCP config created at: %s\n" "$USER_MCP_CONFIG_FILE"
  else
    printf "No user MCP config provided, skipping user MCP config creation.\n"
  fi
}

function create_rules_file() {
  AUGGIE_RULES_FILE="$HOME/.augment/rules.md"
  if [ -n "$ARG_AUGGIE_RULES" ]; then
    mkdir -p "$(dirname "$AUGGIE_RULES_FILE")"
    echo -n "$ARG_AUGGIE_RULES" > "$AUGGIE_RULES_FILE"
    printf "Rules file created at: %s\n" "$AUGGIE_RULES_FILE"
  else
    printf "No rules provided, skipping rules file creation.\n"
  fi
}

install_auggie
create_coder_mcp
create_user_mcp
create_rules_file
