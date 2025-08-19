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

ARG_EXTRA_CODEX_CONFIG=$(echo -n "$ARG_EXTRA_CODEX_CONFIG" | base64 -d)
ARG_ADDITIONAL_EXTENSIONS=$(echo -n "$ARG_ADDITIONAL_EXTENSIONS" | base64 -d)
ARG_CODEX_INSTRUCTION_PROMPT=$(echo -n "$ARG_CODEX_INSTRUCTION_PROMPT" | base64 -d)

echo "--------------------------------"
printf "install: %s\n" "$ARG_INSTALL"
printf "codex_version: %s\n" "$ARG_CODEX_VERSION"
printf "codex_config: %s\n" "$ARG_EXTRA_CODEX_CONFIG"
printf "app_slug: %s\n" "$ARG_CODER_MCP_APP_STATUS_SLUG"
printf "additional_extensions: %s\n" "$ARG_ADDITIONAL_EXTENSIONS"
printf "start_directory: %s\n" "$ARG_CODEX_START_DIRECTORY"
printf "instruction_prompt: %s\n" "$ARG_CODEX_INSTRUCTION_PROMPT"

echo "--------------------------------"

set +o nounset

function install_node() {
  # borrowed from claude-code module
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

function install_codex() {
  if [ "${ARG_INSTALL}" = "true" ]; then
    # we need node to install and run codex-cli
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

    printf "%s Installing Codex CLI\n" "${BOLD}"

    if [ -n "$ARG_CODEX_VERSION" ]; then
      npm install -g "@openai/codex@$ARG_CODEX_VERSION"
    else
      npm install -g "@openai/codex"
    fi
    printf "%s Successfully installed Codex CLI. Version: %s\n" "${BOLD}" "$(codex --version)"
  fi
}

function populate_config_toml() {
  CONFIG_PATH="$HOME/.codex/config.toml"
  mkdir -p "$(dirname "$CONFIG_PATH")"
  printf "Custom codex_config is provided !\n"
  BASE_SANDBOX_CONFIG=$(
    cat << EOF
# Base sandbox configuration for Codex workspace access
# This ensures Codex can read/write files in the specified folder for AI tasks
sandbox_mode = "${ARG_SANDBOX_MODE}"
approval_policy = "${ARG_APPROVAL_POLICY}"

# Allow network access in workspace-write mode for package installation, API calls, etc.
[sandbox_workspace_write]
network_access = ${ARG_NETWORK_ACCESS}
EOF
  )
  
  BASE_EXTENSIONS=$(
    cat << EOF
[mcp_servers.Coder]
command = "coder"
args = ["exp", "mcp", "server"]
env = { "CODER_MCP_APP_STATUS_SLUG" = "${ARG_CODER_MCP_APP_STATUS_SLUG}", "CODER_MCP_AI_AGENTAPI_URL"= "http://localhost:3284", "CODER_AGENT_URL" = "${CODER_AGENT_URL}", "CODER_AGENT_TOKEN" = "${CODER_AGENT_TOKEN}" }
description = "Report ALL tasks and statuses (in progress, done, failed) you are working on."
type = "stdio"
EOF
  )
  
  echo "
${BASE_SANDBOX_CONFIG}

${ARG_EXTRA_CODEX_CONFIG}

${BASE_EXTENSIONS}

${ARG_ADDITIONAL_EXTENSIONS}
    " > "$HOME/.codex/config.toml"

}

function add_instruction_prompt_if_exists() {
  if [ -n "${ARG_CODEX_INSTRUCTION_PROMPT:-}" ]; then
    if [ -d "${ARG_CODEX_START_DIRECTORY}" ]; then
      printf "Directory '%s' exists. Changing to it.\\n" "${ARG_CODEX_START_DIRECTORY}"
      cd "${ARG_CODEX_START_DIRECTORY}" || {
        printf "Error: Could not change to directory '%s'.\\n" "${ARG_CODEX_START_DIRECTORY}"
        exit 1
      }
    else
      printf "Directory '%s' does not exist. Creating and changing to it.\\n" "${ARG_CODEX_START_DIRECTORY}"
      mkdir -p "${ARG_CODEX_START_DIRECTORY}" || {
        printf "Error: Could not create directory '%s'.\\n" "${ARG_CODEX_START_DIRECTORY}"
        exit 1
      }
      cd "${ARG_CODEX_START_DIRECTORY}" || {
        printf "Error: Could not change to directory '%s'.\\n" "${ARG_CODEX_START_DIRECTORY}"
        exit 1
      }
    fi

    # Check if AGENTS.md contains the instruction prompt already
    if [ -f AGENTS.md ] && grep -Fxq "${ARG_CODEX_INSTRUCTION_PROMPT}" AGENTS.md; then
      printf "AGENTS.md already contains the instruction prompt. Skipping append.\n"
    else
      printf "Appending instruction prompt to AGENTS.md\n"
      echo -e "\n${ARG_CODEX_INSTRUCTION_PROMPT}" >> AGENTS.md
    fi
  else
    printf "AGENTS.md is not set.\n"
  fi
}

# Install Codex
install_codex
codex --version
populate_config_toml
add_instruction_prompt_if_exists
