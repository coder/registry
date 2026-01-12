#!/bin/bash

set -euo pipefail

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
ARG_REPORT_TASKS=${ARG_REPORT_TASKS:-true}
ARG_ENABLE_BOUNDARY=${ARG_ENABLE_BOUNDARY:-false}
ARG_BOUNDARY_VERSION=${ARG_BOUNDARY_VERSION:-"latest"}
ARG_COMPILE_FROM_SOURCE=${ARG_COMPILE_FROM_SOURCE:-false}
ARG_CODER_HOST=${ARG_CODER_HOST:-}

echo "--------------------------------"

printf "ARG_MODEL: %s\n" "$ARG_MODEL"
printf "ARG_RESUME: %s\n" "$ARG_RESUME_SESSION_ID"
printf "ARG_CONTINUE: %s\n" "$ARG_CONTINUE"
printf "ARG_DANGEROUSLY_SKIP_PERMISSIONS: %s\n" "$ARG_DANGEROUSLY_SKIP_PERMISSIONS"
printf "ARG_PERMISSION_MODE: %s\n" "$ARG_PERMISSION_MODE"
printf "ARG_AI_PROMPT: %s\n" "$ARG_AI_PROMPT"
printf "ARG_WORKDIR: %s\n" "$ARG_WORKDIR"
printf "ARG_REPORT_TASKS: %s\n" "$ARG_REPORT_TASKS"
printf "ARG_ENABLE_BOUNDARY: %s\n" "$ARG_ENABLE_BOUNDARY"
printf "ARG_BOUNDARY_VERSION: %s\n" "$ARG_BOUNDARY_VERSION"
printf "ARG_COMPILE_FROM_SOURCE: %s\n" "$ARG_COMPILE_FROM_SOURCE"
printf "ARG_CODER_HOST: %s\n" "$ARG_CODER_HOST"

echo "--------------------------------"

function install_boundary() {
  if [ "${ARG_COMPILE_FROM_SOURCE:-false}" = "true" ]; then
    # Install boundary by compiling from source
    echo "Compiling boundary from source (version: $ARG_BOUNDARY_VERSION)"

    echo "Removing existing boundary directory to allow re-running the script safely"
    if [ -d boundary ]; then
      rm -rf boundary
    fi

    echo "Clone boundary repository"
    git clone https://github.com/coder/boundary.git
    cd boundary
    git checkout "$ARG_BOUNDARY_VERSION"

    # Build the binary
    make build

    # Install binary and wrapper script (optional)
    sudo cp boundary /usr/local/bin/
    sudo cp scripts/boundary-wrapper.sh /usr/local/bin/boundary-run
    sudo chmod +x /usr/local/bin/boundary-run
  else
    # Install boundary using official install script
    echo "Installing boundary using official install script (version: $ARG_BOUNDARY_VERSION)"
    curl -fsSL https://raw.githubusercontent.com/coder/boundary/main/install.sh | bash -s -- --version "$ARG_BOUNDARY_VERSION"
  fi
}

function validate_claude_installation() {
  if command_exists claude; then
    printf "Claude Code is installed\n"
  else
    printf "Error: Claude Code is not installed. Please enable install_claude_code or install it manually\n"
    exit 1
  fi
}

# Hardcoded task session ID for Coder task reporting
# This ensures all task sessions use a consistent, predictable ID
TASK_SESSION_ID="cd32e253-ca16-4fd3-9825-d837e74ae3c2"

get_project_dir() {
  local workdir_normalized
  workdir_normalized=$(echo "$ARG_WORKDIR" | tr '/' '-')
  echo "$HOME/.claude/projects/${workdir_normalized}"
}

get_task_session_file() {
  echo "$(get_project_dir)/${TASK_SESSION_ID}.jsonl"
}

task_session_exists() {
  local session_file
  session_file=$(get_task_session_file)

  if [ -f "$session_file" ]; then
    printf "Task session file found: %s\n" "$session_file"
    return 0
  else
    printf "Task session file not found: %s\n" "$session_file"
    return 1
  fi
}

is_valid_session() {
  local session_file="$1"

  # Check if file exists and is not empty
  # Empty files indicate the session was created but never used so they need to be removed
  if [ ! -f "$session_file" ]; then
    printf "Session validation failed: file does not exist\n"
    return 1
  fi

  if [ ! -s "$session_file" ]; then
    printf "Session validation failed: file is empty, removing stale file\n"
    rm -f "$session_file"
    return 1
  fi

  # Check for minimum session content
  # Valid sessions need at least 2 lines: initial message and first response
  local line_count
  line_count=$(wc -l < "$session_file")
  if [ "$line_count" -lt 2 ]; then
    printf "Session validation failed: incomplete (only %s lines), removing incomplete file\n" "$line_count"
    rm -f "$session_file"
    return 1
  fi

  # Validate JSONL format by checking first 3 lines
  # Claude session files use JSONL (JSON Lines) format where each line is valid JSON
  if ! head -3 "$session_file" | jq empty 2> /dev/null; then
    printf "Session validation failed: invalid JSONL format, removing corrupt file\n"
    rm -f "$session_file"
    return 1
  fi

  # Verify the session has a valid sessionId field
  # This ensures the file structure matches Claude's session format
  if ! grep -q '"sessionId"' "$session_file" \
    || ! grep -m 1 '"sessionId"' "$session_file" | jq -e '.sessionId' > /dev/null 2>&1; then
    printf "Session validation failed: no valid sessionId found, removing malformed file\n"
    rm -f "$session_file"
    return 1
  fi

  printf "Session validation passed: %s\n" "$session_file"
  return 0
}

has_any_sessions() {
  local project_dir
  project_dir=$(get_project_dir)

  if [ -d "$project_dir" ] && find "$project_dir" -maxdepth 1 -name "*.jsonl" -size +0c 2> /dev/null | grep -q .; then
    printf "Sessions found in: %s\n" "$project_dir"
    return 0
  else
    printf "No sessions found in: %s\n" "$project_dir"
    return 1
  fi
}

ARGS=()

function start_agentapi() {
  # For Task reporting
  export CODER_MCP_ALLOWED_TOOLS="coder_report_task"

  mkdir -p "$ARG_WORKDIR"
  cd "$ARG_WORKDIR"

  if [ -n "$ARG_MODEL" ]; then
    ARGS+=(--model "$ARG_MODEL")
  fi

  if [ -n "$ARG_PERMISSION_MODE" ]; then
    ARGS+=(--permission-mode "$ARG_PERMISSION_MODE")
  fi

  if [ -n "$ARG_RESUME_SESSION_ID" ]; then
    echo "Resuming specified session: $ARG_RESUME_SESSION_ID"
    ARGS+=(--resume "$ARG_RESUME_SESSION_ID")
    [ "$ARG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ] && ARGS+=(--dangerously-skip-permissions)

  elif [ "$ARG_CONTINUE" = "true" ]; then

    if [ "$ARG_REPORT_TASKS" = "true" ]; then
      local session_file
      session_file=$(get_task_session_file)

      if task_session_exists && is_valid_session "$session_file"; then
        echo "Resuming task session: $TASK_SESSION_ID"
        ARGS+=(--resume "$TASK_SESSION_ID" --dangerously-skip-permissions)
      else
        echo "Starting new task session: $TASK_SESSION_ID"
        ARGS+=(--session-id "$TASK_SESSION_ID" --dangerously-skip-permissions)
        [ -n "$ARG_AI_PROMPT" ] && ARGS+=(-- "$ARG_AI_PROMPT")
      fi

    else
      if has_any_sessions; then
        echo "Continuing most recent standalone session"
        ARGS+=(--continue)
        [ "$ARG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ] && ARGS+=(--dangerously-skip-permissions)
      else
        echo "No sessions found, starting fresh standalone session"
        [ "$ARG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ] && ARGS+=(--dangerously-skip-permissions)
        [ -n "$ARG_AI_PROMPT" ] && ARGS+=(-- "$ARG_AI_PROMPT")
      fi
    fi

  else
    echo "Continue disabled, starting fresh session"
    [ "$ARG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ] && ARGS+=(--dangerously-skip-permissions)
    [ -n "$ARG_AI_PROMPT" ] && ARGS+=(-- "$ARG_AI_PROMPT")
  fi

  printf "Running claude code with args: %s\n" "$(printf '%q ' "${ARGS[@]}")"

  if [ "${ARG_ENABLE_BOUNDARY:-false}" = "true" ]; then
    install_boundary

    printf "Starting with coder boundary enabled\n"

    # Add default allowed URLs
    BOUNDARY_ARGS+=(--allow "domain=anthropic.com" --allow "domain=registry.npmjs.org" --allow "domain=sentry.io" --allow "domain=claude.ai" --allow "domain=$ARG_CODER_HOST")

    agentapi server --type claude --term-width 67 --term-height 1190 -- \
      boundary-run "${BOUNDARY_ARGS[@]}" -- \
      claude "${ARGS[@]}"
  else
    agentapi server --type claude --term-width 67 --term-height 1190 -- claude "${ARGS[@]}"
  fi
}

validate_claude_installation
start_agentapi
