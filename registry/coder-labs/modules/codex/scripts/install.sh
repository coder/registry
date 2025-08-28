#!/bin/bash
source "$HOME"/.bashrc

BOLD='\033[0;1m'

command_exists() {
  command -v "$1" > /dev/null 2>&1
}
set -o errexit
set -o pipefail
set -o nounset

ARG_BASE_CONFIG_TOML=$(echo -n "$ARG_BASE_CONFIG_TOML" | base64 -d)
ARG_ADDITIONAL_MCP_SERVERS=$(echo -n "$ARG_ADDITIONAL_MCP_SERVERS" | base64 -d)
ARG_CODEX_INSTRUCTION_PROMPT=$(echo -n "$ARG_CODEX_INSTRUCTION_PROMPT" | base64 -d)

echo "=== Codex Module Configuration ==="
printf "Install Codex: %s\n" "$ARG_INSTALL"
printf "Codex Version: %s\n" "$ARG_CODEX_VERSION"
printf "App Slug: %s\n" "$ARG_CODER_MCP_APP_STATUS_SLUG"
printf "Start Directory: %s\n" "$ARG_CODEX_START_DIRECTORY"
printf "Has Base Config: %s\n" "$([ -n "$ARG_BASE_CONFIG_TOML" ] && echo "Yes" || echo "No")"
printf "Has Additional MCP: %s\n" "$([ -n "$ARG_ADDITIONAL_MCP_SERVERS" ] && echo "Yes" || echo "No")"
printf "Has System Prompt: %s\n" "$([ -n "$ARG_CODEX_INSTRUCTION_PROMPT" ] && echo "Yes" || echo "No")"
echo "======================================"

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

function install_codex() {
  if [ "${ARG_INSTALL}" = "true" ]; then
    install_node

    if ! command_exists nvm; then
      printf "which node: %s\n" "$(which node)"
      printf "which npm: %s\n" "$(which npm)"

      mkdir -p "$HOME"/.npm-global

      npm config set prefix "$HOME/.npm-global"

      export PATH="$HOME/.npm-global/bin:$PATH"

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

write_minimal_default_config() {
  local config_path="$1"
  cat << EOF > "$config_path"
# Minimal Default Codex Configuration
sandbox_mode = "workspace-write"
approval_policy = "never"
preferred_auth_method = "apikey"

[sandbox_workspace_write]
network_access = true

EOF
}

append_mcp_servers_section() {
  local config_path="$1"

  cat << EOF >> "$config_path"

# MCP Servers Configuration
[mcp_servers.Coder]
command = "coder"
args = ["exp", "mcp", "server"]
env = { "CODER_MCP_APP_STATUS_SLUG" = "${ARG_CODER_MCP_APP_STATUS_SLUG}", "CODER_MCP_AI_AGENTAPI_URL" = "http://localhost:3284", "CODER_AGENT_URL" = "${CODER_AGENT_URL}", "CODER_AGENT_TOKEN" = "${CODER_AGENT_TOKEN}" }
description = "Report ALL tasks and statuses (in progress, done, failed) you are working on."
type = "stdio"

EOF

  if [ -n "$ARG_ADDITIONAL_MCP_SERVERS" ]; then
    printf "Adding additional MCP servers\n"
    echo "$ARG_ADDITIONAL_MCP_SERVERS" >> "$config_path"
  fi
}

function populate_config_toml() {
  CONFIG_PATH="$HOME/.codex/config.toml"
  mkdir -p "$(dirname "$CONFIG_PATH")"

  if [ -n "$ARG_BASE_CONFIG_TOML" ]; then
    printf "Using provided base configuration\n"
    echo "$ARG_BASE_CONFIG_TOML" > "$CONFIG_PATH"
  else
    printf "Using minimal default configuration\n"
    write_minimal_default_config "$CONFIG_PATH"
  fi

  append_mcp_servers_section "$CONFIG_PATH"
}

function add_instruction_prompt_if_exists() {
  if [ -n "${ARG_CODEX_INSTRUCTION_PROMPT:-}" ]; then
    AGENTS_PATH="$HOME/.codex/AGENTS.md"
    printf "Creating AGENTS.md in .codex directory: %s\\n" "${AGENTS_PATH}"

    mkdir -p "$HOME/.codex"

    if [ -f "${AGENTS_PATH}" ] && grep -Fq "${ARG_CODEX_INSTRUCTION_PROMPT}" "${AGENTS_PATH}"; then
      printf "AGENTS.md already contains the instruction prompt. Skipping append.\n"
    else
      printf "Appending instruction prompt to AGENTS.md in .codex directory\n"
      echo -e "\n${ARG_CODEX_INSTRUCTION_PROMPT}" >> "${AGENTS_PATH}"
    fi

    if [ ! -d "${ARG_CODEX_START_DIRECTORY}" ]; then
      printf "Creating start directory '%s'\\n" "${ARG_CODEX_START_DIRECTORY}"
      mkdir -p "${ARG_CODEX_START_DIRECTORY}" || {
        printf "Error: Could not create directory '%s'.\\n" "${ARG_CODEX_START_DIRECTORY}"
        exit 1
      }
    fi
  else
    printf "AGENTS.md instruction prompt is not set.\n"
  fi
}

install_codex
codex --version
populate_config_toml
add_instruction_prompt_if_exists
