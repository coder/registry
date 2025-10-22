#!/bin/bash

set -o errexit
set -o pipefail

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

if command_exists goose; then
  GOOSE_CMD=goose
elif [ -f "$HOME/.local/bin/goose" ]; then
  GOOSE_CMD="$HOME/.local/bin/goose"
else
  echo "Error: Goose is not installed. Please enable install_goose or install it manually."
  exit 1
fi

MODULE_DIR="$HOME/.goose-module"
mkdir -p "$MODULE_DIR"

ARG_SESSION_NAME=${ARG_SESSION_NAME:-}
ARG_DEFAULT_SESSION_NAME=${ARG_DEFAULT_SESSION_NAME:-}
ARG_CONTINUE=${ARG_CONTINUE:-true}

if [ -n "$ARG_SESSION_NAME" ]; then
  SESSION_NAME="$ARG_SESSION_NAME"
else
  SESSION_NAME="$ARG_DEFAULT_SESSION_NAME"
fi

echo "Session name: $SESSION_NAME"

session_name_exists() {
  local name=$1
  "$GOOSE_CMD" session list --format json 2>/dev/null | grep -q "\"name\":[[:space:]]*\"$name\""
}

if [ "$ARG_CONTINUE" = "true" ]; then
  if session_name_exists "$SESSION_NAME"; then
    echo "Resuming session: $SESSION_NAME"
    GOOSE_ARGS=(session --resume --name "$SESSION_NAME")
  else
    echo "Starting new session: $SESSION_NAME"
    if [ -n "$GOOSE_TASK_PROMPT" ]; then
      PROMPT="Review your goosehints. Every step of the way, report tasks to Coder with proper descriptions and statuses. Your task at hand: $GOOSE_TASK_PROMPT"
      PROMPT_FILE="$MODULE_DIR/prompt.txt"
      echo -n "$PROMPT" > "$PROMPT_FILE"
      GOOSE_ARGS=(run --interactive --name "$SESSION_NAME" --instructions "$PROMPT_FILE")
    else
      GOOSE_ARGS=(session --name "$SESSION_NAME")
    fi
  fi
else
  echo "Continue disabled, starting fresh session"
  if [ -n "$GOOSE_TASK_PROMPT" ]; then
    PROMPT="Review your goosehints. Every step of the way, report tasks to Coder with proper descriptions and statuses. Your task at hand: $GOOSE_TASK_PROMPT"
    PROMPT_FILE="$MODULE_DIR/prompt.txt"
    echo -n "$PROMPT" > "$PROMPT_FILE"
    GOOSE_ARGS=(run --interactive --instructions "$PROMPT_FILE")
  else
    GOOSE_ARGS=(session)
  fi
fi

agentapi server --term-width 67 --term-height 1190 -- \
  bash -c "$(printf '%q ' "$GOOSE_CMD" "${GOOSE_ARGS[@]}")"
