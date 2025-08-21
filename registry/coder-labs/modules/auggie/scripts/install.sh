#!/bin/bash
source "$HOME"/.bashrc

BOLD='\033[0;1m'

# Function to check if a command exists
command_exists() {
  command -v "$1" > /dev/null 2>&1
}
set -o errexit
set -o pipefail
set -o nounset

ARG_AUGGIE_INSTALL=${ARG_AUGGIE_INSTALL:-true}
ARG_AUGGIE_VERSION=${ARG_AUGGIE_VERSION:-}
ARG_MCP_APP_STATUS_SLUG=${ARG_MCP_APP_STATUS_SLUG:-}
ARG_AUGGIE_RULES=$(echo -n "${ARG_AUGGIE_RULES:-}" | base64 -d)

echo "--------------------------------"

printf "install auggie: %s\n" "$ARG_AUGGIE_INSTALL"
printf "auggie_version: %s\n" "$ARG_AUGGIE_VERSION"
printf "app_slug: %s\n" "$ARG_MCP_APP_STATUS_SLUG"
printf "rules: %s\n" "$ARG_AUGGIE_RULES"

echo "--------------------------------"

set +o nounset

function install_node() {
  if ! command_exists npm; then
    printf "npm not found, checking for Node.js installation...\n"
    if ! command_exists node; then
      printf "Node.js not found, installing Node.js via NVM...\n"
      export NVM_DIR="$HOME/.nvm"
      if [ ! -d "$NVM_DIR" ]; then
        mkdir -p "$NVM_DIR"
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
      else
        [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
      fi

      nvm install --lts
      nvm use --lts
      nvm alias default node

      printf "Node.js installed: %s\n" "$(node --version)"
      printf "npm installed: %s\n" "$(npm --version)"
    else
      printf "Node.js is installed but npm is not available. Please install npm manually.\n"
      exit 1
    fi
  fi
}

function install_auggie() {
  if [ "${ARG_AUGGIE_INSTALL}" = "true" ]; then
    install_node

    # If nvm does not exist, we will create a global npm directory (this os to prevent the possibility of EACCESS issues on npm -g)
    if ! command_exists nvm; then
      printf "which node: %s\n" "$(which node)"
      printf "which npm: %s\n" "$(which npm)"

      # Create a directory for global packages
      mkdir -p "$HOME"/.npm-global

      # Configure npm to use it
      npm config set prefix "$HOME/.npm-global"

      # Add to PATH for current session
      export PATH="$HOME/.npm-global/bin:$PATH"

      # Add to shell profile for future sessions
      if ! grep -q "export PATH=$HOME/.npm-global/bin:\$PATH" ~/.bashrc; then
        echo "export PATH=$HOME/.npm-global/bin:\$PATH" >> ~/.bashrc
      fi
    fi

    printf "%s Installing Auggie CLI\n" "${BOLD}"

    if [ -n "$ARG_AUGGIE_VERSION" ]; then
      npm install -g "@augmentcode/auggie@$ARG_AUGGIE_VERSION"
    else
      npm install -g "@augmentcode/auggie"
    fi
    printf "%s Successfully installed Auggie CLI. Version: %s\n" "${BOLD}" "$(auggie --version)"
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
       "CODER_AGENT_URL": "${CODER_AGENT_URL}",
       "CODER_AGENT_TOKEN": "${CODER_AGENT_TOKEN}"
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
create_rules_file
