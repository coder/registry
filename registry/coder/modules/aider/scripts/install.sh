#!/bin/bash
set -euo pipefail

# Function to check if a command exists
command_exists() {
  command -v "$1" > /dev/null 2>&1
}

# Inputs
ARG_WORKDIR=${ARG_WORKDIR:-/home/coder}
ARG_INSTALL_AIDER=${ARG_INSTALL_AIDER:-true}
ARG_AIDER_CONFIG=${ARG_AIDER_CONFIG:-}

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
  echo "Aider installed: $(aider --version || echo 'Aider installation check failed')"
}

function configure_aider_settings() {
  if [ -n "${ARG_AIDER_CONFIG}" ]; then
    echo "Configuring Aider environment variables and model"

    mkdir -p "$HOME/.config/aider"

    echo "$ARG_AIDER_CONFIG" > "$HOME/.config/aider/.aider.conf.yml"
    echo "Aider config created at $HOME/.config/aider/.aider.conf.yml"
  else
    printf "No Aider environment variables or model configured\n"
  fi
}

install_aider
configure_aider_settings
