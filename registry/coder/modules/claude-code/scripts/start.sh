#!/bin/bash
set -euo pipefail

if [ -f "$HOME/.bashrc" ]; then
  source "$HOME"/.bashrc
fi
export PATH="$HOME/.local/bin:$PATH"

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

ARG_MODEL=${ARG_MODEL:-}
ARG_RESUME_SESSION_ID=${ARG_RESUME_SESSION_ID:-}
ARG_CONTINUE=${ARG_CONTINUE:-false}
ARG_DANGEROUSLY_SKIP_PERMISSIONS=${ARG_DANGEROUSLY_SKIP_PERMISSIONS:-}
ARG_PERMISSION_MODE=${ARG_PERMISSION_MODE:-}
ARG_WORKDIR=${ARG_WORKDIR:-"$HOME"}
ARG_AI_PROMPT=$(echo -n "${ARG_AI_PROMPT:-}" | base64 -d)

echo "--------------------------------"

printf "ARG_MODEL: %s\n" "$ARG_MODEL"
printf "ARG_RESUME: %s\n" "$ARG_RESUME_SESSION_ID"
printf "ARG_CONTINUE: %s\n" "$ARG_CONTINUE"
printf "ARG_DANGEROUSLY_SKIP_PERMISSIONS: %s\n" "$ARG_DANGEROUSLY_SKIP_PERMISSIONS"
printf "ARG_PERMISSION_MODE: %s\n" "$ARG_PERMISSION_MODE"
printf "ARG_AI_PROMPT: %s\n" "$ARG_AI_PROMPT"
printf "ARG_WORKDIR: %s\n" "$ARG_WORKDIR"

echo "--------------------------------"

# see the remove-last-session-id.sh script for details
# about why we need it
# avoid exiting if the script fails
bash "/tmp/remove-last-session-id.sh" "$(pwd)" 2> /dev/null || true

function validate_claude_installation() {
  if command_exists claude; then
    printf "Claude Code is installed\n"
  else
    printf "Error: Claude Code is not installed. Please enable install_claude_code or install it manually\n"
    exit 1
  fi
}

has_session_for_workdir() {
  local workdir="$1"
  local workdir_abs=$(realpath "$workdir" 2> /dev/null || echo "$workdir")

  local project_dir_name=$(echo "$workdir_abs" | sed 's|/|-|g')
  local project_sessions_dir="$HOME/.claude/projects/$project_dir_name"

  if [ -d "$project_sessions_dir" ]; then
    for file in "$project_sessions_dir"/*.jsonl; do
      [ -f "$file" ] || continue
      if grep -q '"type":"user"' "$file" 2> /dev/null; then
        if grep -q '"isSidechain":false' "$file" 2> /dev/null; then
          return 0
        fi
      fi
    done
  fi
  return 1
}

get_latest_session_id() {
  local workdir="$1"
  local workdir_abs=$(realpath "$workdir" 2> /dev/null || echo "$workdir")
  local project_dir_name=$(echo "$workdir_abs" | sed 's|/|-|g')
  local project_sessions_dir="$HOME/.claude/projects/$project_dir_name"

  if [ ! -d "$project_sessions_dir" ]; then
    return 1
  fi

  local latest_session_id=""
  local latest_time=0

  for file in "$project_sessions_dir"/*.jsonl; do
    [ -f "$file" ] || continue

    if grep -q '"type":"user"' "$file" 2> /dev/null; then
      if grep -q '"isSidechain":false' "$file" 2> /dev/null; then
        local file_time=$(stat -c %Y "$file" 2> /dev/null || stat -f %m "$file" 2> /dev/null || echo 0)
        if [ "$file_time" -gt "$latest_time" ]; then
          latest_time=$file_time
          latest_session_id=$(grep '"isSidechain":false' "$file" | grep '"sessionId"' | head -1 | grep -o '"sessionId":"[^"]*"' | cut -d'"' -f4)
        fi
      fi
    fi
  done

  if [ -n "$latest_session_id" ]; then
    echo "$latest_session_id"
    return 0
  else
    return 1
  fi
}

ARGS=()

function start_agentapi() {
  mkdir -p "$ARG_WORKDIR"
  cd "$ARG_WORKDIR"

  if [ -n "$ARG_MODEL" ]; then
    ARGS+=(--model "$ARG_MODEL")
  fi

  if [ -n "$ARG_PERMISSION_MODE" ]; then
    ARGS+=(--permission-mode "$ARG_PERMISSION_MODE")
  fi

  if [ -n "$ARG_RESUME_SESSION_ID" ]; then
    echo "Using explicit resume_session_id: $ARG_RESUME_SESSION_ID"
    ARGS+=(--resume "$ARG_RESUME_SESSION_ID")
    if [ "$ARG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ]; then
      ARGS+=(--dangerously-skip-permissions)
    fi
  elif [ "$ARG_CONTINUE" = "true" ]; then
    if has_session_for_workdir "$ARG_WORKDIR"; then
      local session_id=$(get_latest_session_id "$ARG_WORKDIR")
      if [ -n "$session_id" ]; then
        echo "Session detected for workdir: $ARG_WORKDIR"
        echo "Latest session ID: $session_id"
        ARGS+=(--resume "$session_id")
        if [ "$ARG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ]; then
          ARGS+=(--dangerously-skip-permissions)
        fi
        echo "Resuming existing session with explicit session ID"
      else
        echo "Could not extract session ID, starting new session"
        if [ -n "$ARG_AI_PROMPT" ]; then
          ARGS+=(--dangerously-skip-permissions "$ARG_AI_PROMPT")
          echo "Starting new session with prompt"
        else
          if [ "$ARG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ]; then
            ARGS+=(--dangerously-skip-permissions)
          fi
          echo "Starting claude code session"
        fi
      fi
    else
      echo "No existing session for workdir: $ARG_WORKDIR"
      if [ -n "$ARG_AI_PROMPT" ]; then
        ARGS+=(--dangerously-skip-permissions "$ARG_AI_PROMPT")
        echo "Starting new session with prompt"
      else
        if [ "$ARG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ]; then
          ARGS+=(--dangerously-skip-permissions)
        fi
        echo "Starting claude code session"
      fi
    fi
  else
    echo "Continue disabled, starting fresh session"
    if [ -n "$ARG_AI_PROMPT" ]; then
      ARGS+=(--dangerously-skip-permissions "$ARG_AI_PROMPT")
      echo "Starting new session with prompt"
    else
      if [ "$ARG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ]; then
        ARGS+=(--dangerously-skip-permissions)
      fi
      echo "Starting claude code session"
    fi
  fi

  printf "Running claude code with args: %s\n" "$(printf '%q ' "${ARGS[@]}")"
  agentapi server --type claude --term-width 67 --term-height 1190 -- claude "${ARGS[@]}"
}

validate_claude_installation
start_agentapi
