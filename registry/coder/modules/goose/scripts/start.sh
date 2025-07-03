#!/bin/bash

set -o errexit
set -o pipefail

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

if command_exists goose; then
    GOOSE_CMD=goose
elif [ -f "$HOME/.local/bin/goose" ]; then
    GOOSE_CMD="$HOME/.local/bin/goose"
else
    echo "Error: Goose is not installed. Please enable install_goose or install it manually."
    exit 1
fi

# this must be kept up to date with main.tf
MODULE_DIR="$HOME/.goose-module"
mkdir -p "$MODULE_DIR"

if [ ! -z "$GOOSE_TASK_PROMPT" ]; then
    echo "Starting with a prompt"
    PROMPT="Review your goosehints. Every step of the way, report tasks to Coder with proper descriptions and statuses. Your task at hand: $GOOSE_TASK_PROMPT"
    PROMPT_FILE="$MODULE_DIR/prompt.txt"
    echo -n "$PROMPT" >"$PROMPT_FILE"
    GOOSE_ARGS=(run --interactive --instructions "$PROMPT_FILE")
else
    echo "Starting without a prompt"
    GOOSE_ARGS=()
fi

agentapi server --term-width 67 --term-height 1190 -- \
    bash -c "$(printf '%q ' "$GOOSE_CMD" "${GOOSE_ARGS[@]}")"
