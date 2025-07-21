#!/bin/bash

BOLD='\033[0;1m'

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

set -o nounset

echo "--------------------------------"
printf "gemini_config: %s\n" "$ARG_GEMINI_CONFIG\n"
printf "install: %s\n" "$ARG_INSTALL\n"
printf "gemini_version: %s\n" "$ARG_GEMINI_VERSION\n"
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

        printf "Node.js installed: %s\n" "$(node --version)\n"
        printf "npm installed: %s\n" "$(npm --version)\n"
      else
        printf "Node.js is installed but npm is not available. Please install npm manually.\n"
        exit 1
      fi
    fi
}

function install_gemini() {
  if [ "${ARG_INSTALL}" = "true" ]; then
    # we need node to install and run gemini-cli
    install_node

    printf "%s Installing Gemini CLI\n" "$${BOLD}"
    if [ -n "$ARG_GEMINI_VERSION" ]; then
      npm install -g "@google/gemini-cli@$ARG_GEMINI_VERSION"
    else
      npm install -g "@google/gemini-cli"
    fi
    printf "%s Successfully installed Gemini CLI. Version: %s" "$${BOLD}" "$(gemini --version)\n"
  fi
}

function populate_settings_json() {
    if [ "${ARG_GEMINI_CONFIG}" != "" ]; then
      echo "${ARG_GEMINI_CONFIG}" > "/home/coder/.gemini/settings.json"
    fi
}



# Install Gemini
install_gemini
populate_settings_json

