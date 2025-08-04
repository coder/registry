#!/bin/bash
set -euo pipefail

# ANSI colors
BOLD='\033[1m'

echo "--------------------------------"
echo "Install flag: $ARG_INSTALL_SOURCEGRAPH_AMP"
echo "Workspace: $SOURCEGRAPH_AMP_START_DIRECTORY"
echo "--------------------------------"

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

function install_sourcegraph_amp() {
    if [ "${ARG_INSTALL_SOURCEGRAPH_AMP}" = "true" ]; then
        install_node

        # If nvm is not used, set up user npm global directory
        if ! command_exists nvm; then
            mkdir -p "$HOME/.npm-global"
            npm config set prefix "$HOME/.npm-global"
            export PATH="$HOME/.npm-global/bin:$PATH"
            if ! grep -q "export PATH=$HOME/.npm-global/bin:\$PATH" ~/.bashrc; then
                echo "export PATH=$HOME/.npm-global/bin:\$PATH" >> ~/.bashrc
            fi
        fi

        printf "%s Installing Sourcegraph AMP CLI...\n" "${BOLD}"
        npm install -g @sourcegraph/amp
        export AMP_API_KEY="$SOURCEGRAPH_AMP_API_KEY"
        printf "%s Successfully installed Sourcegraph AMP CLI. Version: %s\n" "${BOLD}" "$(amp --version)"
    fi
}

install_sourcegraph_amp