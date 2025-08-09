#!/bin/bash

set -o errexit
set -o pipefail

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

AI_PROMPT=${AI_PROMPT:-}
FORCE=${FORCE:-false}
MODEL=${MODEL:-}
OUTPUT_FORMAT=${OUTPUT_FORMAT:-json}
MODULE_DIR_NAME=${MODULE_DIR_NAME:-.cursor-cli-module}
FOLDER=${FOLDER:-$HOME}

mkdir -p "$HOME/$MODULE_DIR_NAME"


# Find cursor agent cli
if command_exists cursor-agent; then
  CURSOR_CMD=cursor-agent
elif [ -x "$HOME/.local/bin/cursor-agent" ]; then
  CURSOR_CMD="$HOME/.local/bin/cursor-agent"
else
  echo "Error: cursor-agent not found. Install it or set install_cursor_cli=true." | tee -a "$HOME/$MODULE_DIR_NAME/start.log"
  exit 1
fi

# Ensure working directory exists
if [ -d "$FOLDER" ]; then
  cd "$FOLDER"
else
  mkdir -p "$FOLDER"
  cd "$FOLDER"
fi

ARGS=()

# global flags
if [ -n "$MODEL" ]; then
  ARGS+=("-m" "$MODEL")
fi
if [ "$FORCE" = "true" ]; then
  ARGS+=("-f")
fi

if [ -n "$AI_PROMPT" ]; then
  ARGS+=("$AI_PROMPT")
fi

# Log and exec
printf "Running: %q %s\n" "$CURSOR_CMD" "$(printf '%q ' "${ARGS[@]}")" | tee -a "$HOME/$MODULE_DIR_NAME/start.log"
exec "$CURSOR_CMD" "${ARGS[@]}"
