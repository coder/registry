#!/bin/bash

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

set -o nounset

echo "--------------------------------"
echo "provider: $ARG_PROVIDER"
echo "model: $ARG_MODEL"
echo "goose_config: $ARG_GOOSE_CONFIG"
echo "install: $ARG_INSTALL"
echo "goose_version: $ARG_GOOSE_VERSION"
echo "--------------------------------"

set +o nounset

if [ "${ARG_INSTALL}" = "true" ]; then
    echo "Installing Goose..."
    parsed_version="${ARG_GOOSE_VERSION}"
    if [ "${ARG_GOOSE_VERSION}" = "stable" ]; then
        parsed_version=""
    fi
    curl -fsSL https://github.com/block/goose/releases/download/stable/download_cli.sh | GOOSE_VERSION="${parsed_version}" CONFIGURE=false bash
    echo "Goose installed"
else
    echo "Skipping Goose installation"
fi

if [ "${ARG_GOOSE_CONFIG}" != "" ]; then
    echo "Configuring Goose..."
    mkdir -p "$HOME/.config/goose"
    echo "GOOSE_PROVIDER: $ARG_PROVIDER" >"$HOME/.config/goose/config.yaml"
    echo "GOOSE_MODEL: $ARG_MODEL" >>"$HOME/.config/goose/config.yaml"
    echo "$ARG_GOOSE_CONFIG" >>"$HOME/.config/goose/config.yaml"
else
    echo "Skipping Goose configuration"
fi

if [ "${GOOSE_SYSTEM_PROMPT}" != "" ]; then
    echo "Setting Goose system prompt..."
    mkdir -p "$HOME/.config/goose"
    echo "$GOOSE_SYSTEM_PROMPT" >"$HOME/.config/goose/.goosehints"
else
    echo "Goose system prompt not set. use the GOOSE_SYSTEM_PROMPT environment variable to set it."
fi

if command_exists goose; then
    GOOSE_CMD=goose
elif [ -f "$HOME/.local/bin/goose" ]; then
    GOOSE_CMD="$HOME/.local/bin/goose"
else
    echo "Error: Goose is not installed. Please enable install_goose or install it manually."
    exit 1
fi
