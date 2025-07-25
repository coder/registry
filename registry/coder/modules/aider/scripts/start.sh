#!/bin/bash

set -o errexit
set -o pipefail

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

if command_exists aider; then
    AIDER_CMD=aider
elif [ -f "$HOME/.local/bin/aider" ]; then
    AIDER_CMD="$HOME/.local/bin/aider"
else
    echo "Error: Aider is not installed. Please enable install_aider or install it manually."
    exit 1
fi

# this must be kept up to date with main.tf
MODULE_DIR="$HOME/.aider-module"
mkdir -p "$MODULE_DIR"

PROMPT_FILE="$MODULE_DIR/prompt.txt"

if [ -n "${AIDER_TASK_PROMPT:-}" ]; then
    echo "Starting with a prompt"
    echo -n "${AIDER_TASK_PROMPT}" >"$PROMPT_FILE"
    AIDER_ARGS=(--message-file "$PROMPT_FILE")
else
    echo "Starting without a prompt"
    AIDER_ARGS=()
fi

agentapi server --term-width 67 --term-height 1190 -- \
    bash -c "$(printf '%q ' "$AIDER_CMD" "${AIDER_ARGS[@]}")"