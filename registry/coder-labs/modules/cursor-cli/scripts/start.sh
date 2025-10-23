#!/bin/bash

set -o errexit
set -o pipefail

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

ARG_AI_PROMPT=$(echo -n "${ARG_AI_PROMPT:-}" | base64 -d)
ARG_FORCE=${ARG_FORCE:-false}
ARG_MODEL=${ARG_MODEL:-}
ARG_CONTINUE=${ARG_CONTINUE:-true}
ARG_RESUME_SESSION_ID=${ARG_RESUME_SESSION_ID:-}
ARG_MODULE_DIR_NAME=${ARG_MODULE_DIR_NAME:-.cursor-cli-module}
ARG_FOLDER=${ARG_FOLDER:-$HOME}

echo "--------------------------------"
echo "folder: $ARG_FOLDER"
echo "ai_prompt: $ARG_AI_PROMPT"
echo "force: $ARG_FORCE"
echo "model: $ARG_MODEL"
echo "continue: $ARG_CONTINUE"
echo "resume_session_id: ${ARG_RESUME_SESSION_ID:-<none>}"
echo "module_dir_name: $ARG_MODULE_DIR_NAME"
echo "--------------------------------"

mkdir -p "$HOME/$ARG_MODULE_DIR_NAME"

SESSION_FILE="$HOME/$ARG_MODULE_DIR_NAME/session_id.txt"

get_stored_session_id() {
  if [ -f "$SESSION_FILE" ]; then
    cat "$SESSION_FILE" | tr -d '\n' || echo ""
  fi
}

store_session_id() {
  echo "$1" > "$SESSION_FILE"
  echo "Stored session ID: $1"
}

# Find cursor agent cli
if command_exists cursor-agent; then
  CURSOR_CMD=cursor-agent
elif [ -x "$HOME/.local/bin/cursor-agent" ]; then
  CURSOR_CMD="$HOME/.local/bin/cursor-agent"
else
  echo "Error: cursor-agent not found. Install it or set install_cursor_cli=true."
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

if [ -n "$ARG_RESUME_SESSION_ID" ]; then
  echo "Using explicit resume_session_id: $ARG_RESUME_SESSION_ID"
  ARGS+=("--resume" "$ARG_RESUME_SESSION_ID")

elif [ "$ARG_CONTINUE" = "true" ]; then
  STORED_SESSION=$(get_stored_session_id)

  if [ -n "$STORED_SESSION" ]; then
    echo "Found existing session: $STORED_SESSION"
    echo "Resuming conversation..."
    ARGS+=("--resume" "$STORED_SESSION")
  else
    echo "No existing session found"
    echo "Creating new session for this workspace..."
    NEW_SESSION=$($CURSOR_CMD create-chat 2>&1 | tr -d '\n')
    if [ -n "$NEW_SESSION" ]; then
      store_session_id "$NEW_SESSION"
      ARGS+=("--resume" "$NEW_SESSION")
    else
      echo "Warning: Failed to create session, continuing without session resume"
    fi
  fi

else
  echo "Continue disabled, starting fresh session"
  rm -f "$SESSION_FILE"
fi

if [ -n "$ARG_AI_PROMPT" ]; then
  printf "AI prompt provided\n"
  ARGS+=("Complete the task at hand in one go. Every step of the way, report your progress using coder_report_task tool with proper summary and statuses. Your task at hand: $ARG_AI_PROMPT")
fi

# Log and run in background, redirecting all output to the log file
printf "Running: %q %s\n" "$CURSOR_CMD" "$(printf '%q ' "${ARGS[@]}")"

agentapi server --type cursor --term-width 67 --term-height 1190 -- "$CURSOR_CMD" "${ARGS[@]}"
