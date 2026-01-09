#!/bin/bash
set -euo pipefail

# ANSI colors
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ARG_INSTALL_AMP=${ARG_INSTALL_AMP:-true}
ARG_INSTALL_VIA_NPM=${ARG_INSTALL_VIA_NPM:-false}
ARG_AMP_VERSION=${ARG_AMP_VERSION:-}
ARG_AMP_INSTRUCTION_PROMPT=$(echo -n "${ARG_AMP_INSTRUCTION_PROMPT:-}" | base64 -d)
ARG_AMP_CONFIG=$(echo -n "${ARG_AMP_CONFIG:-}" | base64 -d)

echo "--------------------------------"
printf "Install flag: %s\n" "$ARG_INSTALL_AMP"
printf "Install via npm: %s\n" "$ARG_INSTALL_VIA_NPM"
printf "Amp Version: %s\n" "$ARG_AMP_VERSION"
printf "AMP Config: %s\n" "$ARG_AMP_CONFIG"
printf "Instruction Prompt: %s\n" "$ARG_AMP_INSTRUCTION_PROMPT"
echo "--------------------------------"

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

install_amp_npm() {
  printf "%s${YELLOW}Installing Amp via npm${NC}\n" "${BOLD}"

  # Load nvm if available
  # shellcheck source=/dev/null
  if [ -f "$HOME/.nvm/nvm.sh" ]; then
    source "$HOME/.nvm/nvm.sh"
  fi

  if ! command_exists node || ! command_exists npm; then
    printf "${YELLOW}Warning: Node.js/npm not found. Skipping Amp installation.${NC}\n"
    printf "To install Amp via npm, please install Node.js and npm first.\n"
    return 1
  fi

  printf "Node.js version: %s\n" "$(node --version)"
  printf "npm version: %s\n" "$(npm --version)"

  NPM_GLOBAL_PREFIX="${HOME}/.npm-global"
  if [ ! -d "$NPM_GLOBAL_PREFIX" ]; then
    mkdir -p "$NPM_GLOBAL_PREFIX"
  fi

  npm config set prefix "$NPM_GLOBAL_PREFIX"
  export PATH="$NPM_GLOBAL_PREFIX/bin:$PATH"

  if [ -n "$ARG_AMP_VERSION" ]; then
    npm install -g "@sourcegraph/amp@$ARG_AMP_VERSION"
  else
    npm install -g "@sourcegraph/amp"
  fi

  if ! grep -q 'export PATH="$HOME/.npm-global/bin:$PATH"' "$HOME/.bashrc"; then
    echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.bashrc"
  fi
}

install_amp_official() {
  printf "%s Installing Amp using official installer\n" "${BOLD}"

  if [ -n "$ARG_AMP_VERSION" ]; then
    export AMP_VERSION="$ARG_AMP_VERSION"
    printf "Installing Amp version: %s\n" "$AMP_VERSION"
  fi

  if curl -fsSL https://ampcode.com/install.sh | bash; then
    export PATH="$HOME/.local/bin:$HOME/.amp/bin:$PATH"

    if ! grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.bashrc"; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
    fi
  else
    printf "${YELLOW}Warning: Official installer failed. Installation skipped.${NC}\n"
    return 1
  fi
}

function install_amp() {
  if [ "${ARG_INSTALL_AMP}" = "true" ]; then
    if [ "${ARG_INSTALL_VIA_NPM}" = "true" ]; then
      install_amp_npm || {
        printf "${YELLOW}Amp installation via npm failed.${NC}\n"
        return 0
      }
    else
      install_amp_official || {
        printf "${YELLOW}Amp installation via official installer failed.${NC}\n"
        return 0
      }
    fi

    if command_exists amp; then
      printf "%s${GREEN}Successfully installed Sourcegraph Amp CLI. Version: %s${NC}\n" "${BOLD}" "$(amp --version)"
    fi
  else
    printf "Skipping Sourcegraph Amp CLI installation (install_amp=false)\n"
  fi
}

function setup_instruction_prompt() {
  if [ -n "${ARG_AMP_INSTRUCTION_PROMPT:-}" ]; then
    echo "Setting AMP instruction prompt..."
    mkdir -p "$HOME/.config"
    echo "$ARG_AMP_INSTRUCTION_PROMPT" > "$HOME/.config/AGENTS.md"
    echo "Instruction prompt saved to $HOME/.config/AGENTS.md"
  else
    echo "No instruction prompt provided for Sourcegraph AMP."
  fi
}

function configure_amp_settings() {
  echo "Configuring AMP settings..."
  SETTINGS_PATH="$HOME/.config/amp/settings.json"
  mkdir -p "$(dirname "$SETTINGS_PATH")"

  if [ -z "${ARG_AMP_CONFIG:-}" ]; then
    echo "No AMP config provided, skipping configuration"
    return
  fi

  echo "Writing AMP configuration to $SETTINGS_PATH"
  UPDATED_CONFIG=$(echo "$ARG_AMP_CONFIG" | jq --arg token "$CODER_AGENT_TOKEN" --arg url "$CODER_AGENT_URL" \
    ".[\"amp.mcpServers\"].coder.env += {
      \"CODER_AGENT_TOKEN\": \"$CODER_AGENT_TOKEN\",
      \"CODER_AGENT_URL\": \"$CODER_AGENT_URL\"
    }")
  printf "UPDATED_CONFIG: %s\n" "$UPDATED_CONFIG"
  printf '%s\n' "$UPDATED_CONFIG" > "$SETTINGS_PATH"

  echo "AMP configuration complete"
}

install_amp
setup_instruction_prompt
configure_amp_settings
