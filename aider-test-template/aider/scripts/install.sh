#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

set -o nounset

echo "--------------------------------"
echo "provider: $ARG_PROVIDER"
echo "model: $ARG_MODEL"
echo "aider_config: $ARG_AIDER_CONFIG"
echo "install: $ARG_INSTALL"
echo "aider_version: $ARG_AIDER_VERSION"
echo "--------------------------------"

set +o nounset

if [ "${ARG_INSTALL}" = "true" ]; then
    echo "Installing Aider..."
    if ! command_exists python3 || ! command_exists pip3; then
        echo "Installing Python dependencies required for Aider..."
        if command -v apt-get >/dev/null 2>&1; then
            if command -v sudo >/dev/null 2>&1; then
                sudo apt-get update -qq
                sudo apt-get install -y -qq python3-pip python3-venv
            else
                apt-get update -qq || echo "Warning: Cannot update package lists without sudo privileges"
                apt-get install -y -qq python3-pip python3-venv || echo "Warning: Cannot install Python packages without sudo privileges"
            fi
        elif command -v dnf >/dev/null 2>&1; then
            if command -v sudo >/dev/null 2>&1; then
                sudo dnf install -y -q python3-pip python3-virtualenv
            else
                dnf install -y -q python3-pip python3-virtualenv || echo "Warning: Cannot install Python packages without sudo privileges"
            fi
        else
            echo "Warning: Unable to install Python on this system. Neither apt-get nor dnf found."
        fi
    else
        echo "Python is already installed, skipping installation."
    fi

    if ! command_exists aider; then
        curl -LsSf https://aider.chat/install.sh | sh
    fi

    if [ -f "$HOME/.bashrc" ]; then
        if ! grep -q 'export PATH="$HOME/bin:$PATH"' "$HOME/.bashrc"; then
            echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
        fi
    fi

    if [ -f "$HOME/.zshrc" ]; then
        if ! grep -q 'export PATH="$HOME/bin:$PATH"' "$HOME/.zshrc"; then
            echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.zshrc"
        fi
    fi
else
    echo "Skipping Aider installation"
fi

if [ "${ARG_AIDER_CONFIG}" != "" ]; then
    echo "Configuring Aider..."
    mkdir -p "$HOME/.config/aider"
    echo "model: $ARG_MODEL" > "$HOME/.config/aider/config.yml"
    echo "$ARG_AIDER_CONFIG" >> "$HOME/.config/aider/config.yml"
else
    echo "Skipping Aider configuration"
fi