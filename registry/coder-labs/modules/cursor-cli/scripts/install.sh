#!/bin/bash

set -o errexit
set -o pipefail

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Inputs
ARG_INSTALL=${ARG_INSTALL:-true}
ARG_VERSION=${ARG_VERSION:-latest}
MODULE_DIR_NAME=${MODULE_DIR_NAME:-.cursor-cli-module}
FOLDER=${FOLDER:-$HOME}

mkdir -p "$HOME/$MODULE_DIR_NAME"

ADDITIONAL_SETTINGS=$(echo -n "$ADDITIONAL_SETTINGS" | base64 -d)

{
  echo "--------------------------------"
  echo "install: $ARG_INSTALL"
  echo "version: $ARG_VERSION"
  echo "folder: $FOLDER"
  echo "--------------------------------"
} | tee -a "$HOME/$MODULE_DIR_NAME/install.log"

# Install Cursor Agent CLI if requested.
# The docs show Cursor Agent CLI usage; we will install via npm globally.
# This requires Node/npm; install Node via NVM if not present (similar to gemini module approach).
if [ "$ARG_INSTALL" = "true" ]; then
  echo "Installing Cursor Agent CLI..." | tee -a "$HOME/$MODULE_DIR_NAME/install.log"

  install_node() {
    if ! command_exists npm; then
      if ! command_exists node; then
        export NVM_DIR="$HOME/.nvm"
        if [ ! -d "$NVM_DIR" ]; then
          mkdir -p "$NVM_DIR"
          curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
          [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        else
          [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
        fi
        nvm install --lts
        nvm use --lts
        nvm alias default node
      else
        echo "Node is installed but npm missing; please install npm manually." | tee -a "$HOME/$MODULE_DIR_NAME/install.log"
      fi
    fi
  }

  install_node

  # If nvm not present, create local npm global dir to avoid permissions issues
  if ! command_exists nvm; then
    mkdir -p "$HOME/.npm-global"
    npm config set prefix "$HOME/.npm-global"
    export PATH="$HOME/.npm-global/bin:$PATH"
    if ! grep -q "export PATH=$HOME/.npm-global/bin:\$PATH" "$HOME/.bashrc" 2>/dev/null; then
      echo "export PATH=$HOME/.npm-global/bin:\$PATH" >> "$HOME/.bashrc"
    fi
  fi

  if [ -n "$ARG_VERSION" ] && [ "$ARG_VERSION" != "latest" ]; then
    npm install -g "cursor-agent@$ARG_VERSION" 2>&1 | tee -a "$HOME/$MODULE_DIR_NAME/install.log"
  else
    npm install -g cursor-agent 2>&1 | tee -a "$HOME/$MODULE_DIR_NAME/install.log"
  fi

  echo "Installed cursor-agent: $(command -v cursor-agent || true)" | tee -a "$HOME/$MODULE_DIR_NAME/install.log"
fi

# Ensure settings path exists and merge additional_settings JSON
SETTINGS_PATH="$HOME/.cursor/settings.json"
mkdir -p "$(dirname "$SETTINGS_PATH")"

# If settings file doesn't exist, initialize basic structure
if [ ! -f "$SETTINGS_PATH" ]; then
  echo '{}' > "$SETTINGS_PATH"
fi

if [ -n "$ADDITIONAL_SETTINGS" ]; then
  echo "Merging additional settings into $SETTINGS_PATH" | tee -a "$HOME/$MODULE_DIR_NAME/install.log"
  TMP_SETTINGS=$(mktemp)
  # Merge JSON: deep merge mcpServers and top-level keys
  jq --argjson add "$ADDITIONAL_SETTINGS" 'def deepmerge(a;b): reduce (b|keys[]) as $key (a; .[$key] = if ( (.[ $key ]|type?) == "object" and (b[$key]|type?) == "object" ) then deepmerge(.[ $key ]; b[$key]) else b[$key] end); deepmerge(.;$add)' "$SETTINGS_PATH" > "$TMP_SETTINGS" && mv "$TMP_SETTINGS" "$SETTINGS_PATH"
fi

exit 0
