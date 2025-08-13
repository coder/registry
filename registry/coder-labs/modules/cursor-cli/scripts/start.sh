#!/bin/bash

set -o errexit
set -o pipefail

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

ARG_AI_PROMPT=$(echo -n "${ARG_AI_PROMPT:-}" | base64 -d)
ARG_FORCE=${ARG_FORCE:-false}
ARG_MODEL=${ARG_MODEL:-}
ARG_OUTPUT_FORMAT=${ARG_OUTPUT_FORMAT:-json}
ARG_MODULE_DIR_NAME=${ARG_MODULE_DIR_NAME:-.cursor-cli-module}
ARG_FOLDER=${ARG_FOLDER:-$HOME}
ARG_AGENTAPI_MODE=${ARG_AGENTAPI_MODE:-false}

{
  echo "--------------------------------"
  echo "install: $ARG_INSTALL"
  echo "version: $ARG_VERSION"
  echo "folder: $FOLDER"
  echo "ai_prompt: $ARG_AI_PROMPT"
  echo "force: $ARG_FORCE"
  echo "model: $ARG_MODEL"
  echo "output_format: $ARG_OUTPUT_FORMAT"
  echo "module_dir_name: $ARG_MODULE_DIR_NAME"
  echo "folder: $ARG_FOLDER"
  echo "agentapi_mode: $ARG_AGENTAPI_MODE"
  echo "--------------------------------"
} | tee -a "$HOME/$MODULE_DIR_NAME/start.log"


mkdir -p "$HOME/$ARG_MODULE_DIR_NAME"


# Find cursor agent cli
if command_exists cursor-agent; then
  CURSOR_CMD=cursor-agent
elif [ -x "$HOME/.local/bin/cursor-agent" ]; then
  CURSOR_CMD="$HOME/.local/bin/cursor-agent"
else
  echo "Error: cursor-agent not found. Install it or set install_cursor_cli=true." | tee -a "$HOME/$ARG_MODULE_DIR_NAME/start.log"
  exit 1
fi

# Ensure working directory exists
if [ -d "$ARG_FOLDER" ]; then
  cd "$ARG_FOLDER"
else
  mkdir -p "$ARG_FOLDER"
  cd "$ARG_FOLDER"
fi

ARGS=()

# global flags
if [ -n "$ARG_MODEL" ]; then
  ARGS+=("-m" "$ARG_MODEL")
fi
if [ "$ARG_FORCE" = "true" ]; then
  ARGS+=("-f")
fi

if [ -n "$ARG_AI_PROMPT" ]; then
  printf "AI prompt provided\n"
  if [ "$ARG_AGENTAPI_MODE" = "true" ]; then
    ARGS+=("Complete the task at hand and at every step of the way, report tasks to Coder with proper summary and statuses. Your task at hand: $ARG_AI_PROMPT")
  elif [ "$ARG_AI_PROMPT" ]; then
    ARGS+=("$ARG_AI_PROMPT")
  fi
fi

# Log and run in background, redirecting all output to the log file
printf "Running: %q %s\n" "$CURSOR_CMD" "$(printf '%q ' "${ARGS[@]}")" | tee -a "$HOME/$ARG_MODULE_DIR_NAME/start.log"

if [ "$ARG_AGENTAPI_MODE" = "true" ]; then
  agentapi server --term-width 67 --term-height 1190 -- "$CURSOR_CMD" "${ARGS[@]}"
else
  ("$CURSOR_CMD" "${ARGS[@]}" >> "$HOME/$ARG_MODULE_DIR_NAME/start.log" 2>&1) &
fi
