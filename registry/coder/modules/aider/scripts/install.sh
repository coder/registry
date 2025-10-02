#!/bin/bash
set -euo pipefail

# Function to check if a command exists
command_exists() {
  command -v "$1" > /dev/null 2>&1
}

# Inputs
ARG_WORKDIR=${ARG_WORKDIR:-/home/coder}
ARG_INSTALL_AIDER=${ARG_INSTALL_AIDER:-true}
AIDER_SYSTEM_PROMPT=${AIDER_SYSTEM_PROMPT:-}
ARG_REPORT_TASKS=${ARG_REPORT_TASKS:-true}
ARG_AIDER_CONFIG=${ARG_AIDER_CONFIG:-}
ARG_MCP_APP_STATUS_SLUG=${ARG_MCP_APP_STATUS_SLUG:-}

echo "--------------------------------"
echo "Install flag: $ARG_INSTALL_AIDER"
echo "Workspace: $ARG_WORKDIR"
echo "--------------------------------"

function install_aider() {
  echo "pipx installing..."
  sudo apt-get install -y pipx
  echo "pipx installed!"
  pipx ensurepath
  mkdir -p "$ARG_WORKDIR/.local/bin"
  export PATH="$HOME/.local/bin:$ARG_WORKDIR/.local/bin:$PATH"

  if ! command_exists aider; then
    echo "Installing Aider via pipx..."
    pipx install --force aider-install
    aider-install
  fi
  echo "Aider installed: $(aider --version || echo 'check failed the Aider module insatllation failed')"
}

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

      # Temporarily disable nounset (-u) for nvm to avoid PROVIDED_VERSION error
      set +u
      nvm install --lts
      nvm use --lts
      nvm alias default node
      set -u

      printf "Node.js installed: %s\n" "$(node --version)"
      printf "npm installed: %s\n" "$(npm --version)"
    else
      printf "Node.js is installed but npm is not available. Please install npm manually.\n"
      exit 1
    fi
  fi
}

function install_mcpm-aider() {
  install_node

  # If nvm is not used, set up user npm global directory
  if ! command_exists nvm; then
    mkdir -p "$HOME/.npm-global"
    npm config set prefix "$HOME/.npm-global"
    export PATH="$HOME/.npm-global/bin:$PATH"
    if ! grep -q "export PATH=$HOME/.npm-global/bin:\$PATH" ~/.bashrc; then
      echo "export PATH=$HOME/.npm-global/bin:\$PATH" >> ~/.bashrc
    fi
  fi
  printf "%s Installing MCPM-Aider for supporting coder MCP...\n" "${BOLD}"
  npm install -g @poai/mcpm-aider
  printf "%s Successfully installed MCPM-Aider. Version: %s\n" "${BOLD}" "$(mcpm-aider -V)"
}

function setup_system_prompt() {
  if [ -n "${AIDER_SYSTEM_PROMPT:-}" ]; then
    echo "Setting Aider system prompt..."
    mkdir -p "$HOME/.aider-module"
    echo "$AIDER_SYSTEM_PROMPT" > "$HOME/.aider-module/SYSTEM_PROMPT.md"
    echo "System prompt saved to $HOME/.aider-module/SYSTEM_PROMPT.md"
  else
    echo "No system prompt provided for Aider."
  fi
}

function configure_aider_settings() {
  if [ "${ARG_REPORT_TASKS}" = "true" ]; then
    echo "Configuring Aider to report tasks via Coder MCP..."

    mkdir -p "$HOME/.config/aider"

    echo "$ARG_AIDER_CONFIG" > "$HOME/.config/aider/.aider.conf.yml"
    echo "Added Coder MCP extension to Aider config.yml"
  else
    printf "MCP Server not Implemented"
  fi
}

function report_tasks() {
  if [ "$ARG_REPORT_TASKS" = "true" ]; then
    echo "Configuring Aider to report tasks via Coder MCP..."
    export CODER_MCP_APP_STATUS_SLUG="$ARG_MCP_APP_STATUS_SLUG"
    export CODER_MCP_AI_AGENTAPI_URL="http://localhost:3284"
    coder exp mcp configure mcpm-aider "$ARG_WORKDIR"
  else
    export CODER_MCP_APP_STATUS_SLUG=""
    export CODER_MCP_AI_AGENTAPI_URL=""
    echo "Configuring Aider with Coder MCP..."
    coder exp mcp configure mcpm-aider "$ARG_WORKDIR"
  fi
}

install_aider
install_mcpm-aider
setup_system_prompt
configure_aider_settings
report_tasks