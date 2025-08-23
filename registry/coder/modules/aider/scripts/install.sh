#!/bin/bash
set -euo pipefail

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

echo "--------------------------------"
echo "Install flag: $ARG_INSTALL_AIDER"
echo "Workspace: $AIDER_START_DIRECTORY"
echo "--------------------------------"

function install_aider() {
    echo "checking pipx installed..."
    if ! command_exists pipx; then
      echo "pipx not found"
      echo "Installing pipx via apt-get..."
      sudo apt-get update -y
      sudo apt-get install -y pipx
      echo "pipx installed!"
    fi  
    pipx ensurepath 
    echo $PATH
    mkdir -p "$AIDER_START_DIRECTORY/.local/bin"
    export PATH="$HOME/.local/bin:$AIDER_START_DIRECTORY/.local/bin:$PATH"   # ensure in current shell too
    
    if ! command_exists aider; then
      echo "Installing Aider via pipx..."
      pipx install --force aider-install
      aider-install
    fi  
    echo "Aider installed: $(aider --version || echo 'check failed the Aider module insatllation failed')"
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

function configure_aider_settings(){
  if [ "${ARG_IMPLEMENT_MCP}" = "true" ]; then
    echo "Configuring Aider to report tasks via Coder MCP..."

    mkdir -p "$HOME/.config/aider"

    echo $ARG_AIDER_CONFIG > "$HOME/.config/aider/config.yml" 
    echo "Added Coder MCP extension to Aider config.yml"
  else 
    printf "MCP Server not Implemented"
  fi
}



install_aider
setup_system_prompt
configure_aider_settings