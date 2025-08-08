#!/bin/bash

# Function to check if a command exists
command_exists() {
  command -v "$1" > /dev/null 2>&1
}

set -o nounset

echo "--------------------------------"
echo "folder: $ARG_FOLDER"
echo "install: $ARG_INSTALL"
echo "--------------------------------"

set +o nounset

if [ "${ARG_INSTALL}" = "true" ]; then
  echo "Installing Cursor CLI..."

  # Install Cursor CLI using the official installer
  curl https://cursor.com/install -fsS | bash

  # Add cursor-agent to PATH if not already there
  if ! command_exists cursor-agent; then
    echo 'export PATH="$HOME/.cursor/bin:$PATH"' >> "$HOME/.bashrc"
    echo 'export PATH="$HOME/.cursor/bin:$PATH"' >> "$HOME/.zshrc" 2> /dev/null || true
    export PATH="$HOME/.cursor/bin:$PATH"
  fi

  echo "Cursor CLI installed"
else
  echo "Skipping Cursor CLI installation"
fi

# Verify installation
if command_exists cursor-agent; then
  CURSOR_CMD=cursor-agent
elif [ -f "$HOME/.cursor/bin/cursor-agent" ]; then
  CURSOR_CMD="$HOME/.cursor/bin/cursor-agent"
else
  echo "Warning: Cursor CLI is not installed or not found in PATH. Please enable install_cursor_cli or install it manually."
  echo "You can install it manually with: curl https://cursor.com/install -fsS | bash"
fi

echo "Cursor CLI setup complete"
