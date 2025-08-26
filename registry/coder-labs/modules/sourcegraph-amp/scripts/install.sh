#!/bin/bash
set -euo pipefail

source "$HOME"/.bashrc

# ANSI colors
BOLD='\033[1m'

ARG_INSTALL_SOURCEGRAPH_AMP=${ARG_INSTALL_SOURCEGRAPH_AMP:-true}
ARG_AMP_VERSION=${ARG_AMP_VERSION:-}
ARG_AMP_CONFIG=${ARG_AMP_CONFIG:-}
ARG_SOURCEGRAPH_AMP_SYSTEM_PROMPT=${ARG_SOURCEGRAPH_AMP_SYSTEM_PROMPT:-}

echo "--------------------------------"
printf "Install flag: %s\n" "$ARG_INSTALL_SOURCEGRAPH_AMP"
printf "Amp Version: %s\n" "$ARG_AMP_VERSION"
printf "AMP Config: %s\n" "$ARG_AMP_CONFIG"
printf "System Prompt: %s\n" "$ARG_SOURCEGRAPH_AMP_SYSTEM_PROMPT"
echo "--------------------------------"

# Helper function to check if a command exists
command_exists() {
  command -v "$1" > /dev/null 2>&1
}

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

function install_sourcegraph_amp() {
  if [ "${ARG_INSTALL_SOURCEGRAPH_AMP}" = "true" ]; then
    check_dependencies

    printf "%s Installing Sourcegraph amp\n" "${BOLD}"

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

    if ! grep -q "export PATH=\"\$HOME/.npm-global/bin:\$PATH\"" "$HOME/.bashrc"; then
      echo 'export PATH="$HOME/.npm-global/bin:$PATH"' >> "$HOME/.bashrc"
    fi

    printf "%s Successfully installed Sourcegraph Amp CLI. Version: %s\n" "${BOLD}" "$(amp --version)"
  else
    printf "Skipping Sourcegraph Amp CLI installation (install_sourcegraph_amp=false)\n"
  fi
}

function setup_system_prompt() {
  if [ -n "${ARG_SOURCEGRAPH_AMP_SYSTEM_PROMPT:-}" ]; then
    echo "Setting Sourcegraph AMP system prompt..."
    mkdir -p "$HOME/.sourcegraph-amp-module"
    echo "$ARG_SOURCEGRAPH_AMP_SYSTEM_PROMPT" > "$HOME/.sourcegraph-amp-module/SYSTEM_PROMPT.md"
    echo "System prompt saved to $HOME/.sourcegraph-amp-module/SYSTEM_PROMPT.md"
  else
    echo "No system prompt provided for Sourcegraph AMP."
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
  printf '%s\n' "$ARG_AMP_CONFIG" > "$SETTINGS_PATH"

  echo "AMP configuration complete"
}

install_sourcegraph_amp
setup_system_prompt
configure_amp_settings
