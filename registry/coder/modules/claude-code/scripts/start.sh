#!/bin/bash

# Set strict error handling AFTER sourcing bashrc to avoid unbound variable errors from user dotfiles
set -euo pipefail

true > "$HOME/start.log"

log() {
    printf "$@" >> "$HOME/start.log"
}

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
ARG_BOUNDARY_VERSION=${ARG_BOUNDARY_VERSION:-"main"}
ARG_BOUNDARY_LOG_DIR=${ARG_BOUNDARY_LOG_DIR:-"/tmp/boundary_logs"}
ARG_BOUNDARY_LOG_LEVEL=${ARG_BOUNDARY_LOG_LEVEL:-"WARN"}
ARG_BOUNDARY_PROXY_PORT=${ARG_BOUNDARY_PROXY_PORT:-"8087"}
ARG_ENABLE_BOUNDARY_PPROF=${ARG_ENABLE_BOUNDARY_PPROF:-false}
ARG_BOUNDARY_PPROF_PORT=${ARG_BOUNDARY_PPROF_PORT:-"6067"}
ARG_COMPILE_FROM_SOURCE=${ARG_COMPILE_FROM_SOURCE:-false}
ARG_CODER_HOST=${ARG_CODER_HOST:-}

log "--------------------------------"

log "ARG_MODEL: %s\n" "$ARG_MODEL"
log "ARG_RESUME: %s\n" "$ARG_RESUME_SESSION_ID"
log "ARG_CONTINUE: %s\n" "$ARG_CONTINUE"
log "ARG_DANGEROUSLY_SKIP_PERMISSIONS: %s\n" "$ARG_DANGEROUSLY_SKIP_PERMISSIONS"
log "ARG_PERMISSION_MODE: %s\n" "$ARG_PERMISSION_MODE"
log "ARG_AI_PROMPT: %s\n" "$ARG_AI_PROMPT"
log "ARG_WORKDIR: %s\n" "$ARG_WORKDIR"
log "ARG_REPORT_TASKS: %s\n" "$ARG_REPORT_TASKS"
log "ARG_ENABLE_BOUNDARY: %s\n" "$ARG_ENABLE_BOUNDARY"
log "ARG_BOUNDARY_VERSION: %s\n" "$ARG_BOUNDARY_VERSION"
log "ARG_BOUNDARY_LOG_DIR: %s\n" "$ARG_BOUNDARY_LOG_DIR"
log "ARG_BOUNDARY_LOG_LEVEL: %s\n" "$ARG_BOUNDARY_LOG_LEVEL"
log "ARG_BOUNDARY_PROXY_PORT: %s\n" "$ARG_BOUNDARY_PROXY_PORT"
log "ARG_COMPILE_FROM_SOURCE: %s\n" "$ARG_COMPILE_FROM_SOURCE"
log "ARG_CODER_HOST: %s\n" "$ARG_CODER_HOST"

log "--------------------------------"

function install_boundary() {
  if [ "${ARG_COMPILE_FROM_SOURCE:-false}" = "true" ]; then
    # Install boundary by compiling from source
    log "Compiling boundary from source (version: $ARG_BOUNDARY_VERSION)"
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
    log "Installing boundary using official install script (version: $ARG_BOUNDARY_VERSION)"
    curl -fsSL https://raw.githubusercontent.com/coder/boundary/main/install.sh | bash -s -- --version "$ARG_BOUNDARY_VERSION"
  fi
}

function validate_claude_installation() {
  if command_exists claude; then
    log "Claude Code is installed\n"
  else
    log "Error: Claude Code is not installed. Please enable install_claude_code or install it manually\n"
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
    log "Task session file found: %s\n" "$session_file"
    return 0
  else
    log "Task session file not found: %s\n" "$session_file"
    return 1
  fi
}

is_valid_session() {
  local session_file="$1"

  # Check if file exists and is not empty
  # Empty files indicate the session was created but never used so they need to be removed
  if [ ! -f "$session_file" ]; then
    log "Session validation failed: file does not exist\n"
    return 1
  fi

  if [ ! -s "$session_file" ]; then
    log "Session validation failed: file is empty, removing stale file\n"
    rm -f "$session_file"
    return 1
  fi

  # Check for minimum session content
  # Valid sessions need at least 2 lines: initial message and first response
  local line_count
  line_count=$(wc -l < "$session_file")
  if [ "$line_count" -lt 2 ]; then
    log "Session validation failed: incomplete (only %s lines), removing incomplete file\n" "$line_count"
    rm -f "$session_file"
    return 1
  fi

  # Validate JSONL format by checking first 3 lines
  # Claude session files use JSONL (JSON Lines) format where each line is valid JSON
  if ! head -3 "$session_file" | jq empty 2> /dev/null; then
    log "Session validation failed: invalid JSONL format, removing corrupt file\n"
    rm -f "$session_file"
    return 1
  fi

  # Verify the session has a valid sessionId field
  # This ensures the file structure matches Claude's session format
  if ! grep -q '"sessionId"' "$session_file" \
    || ! grep -m 1 '"sessionId"' "$session_file" | jq -e '.sessionId' > /dev/null 2>&1; then
    log "Session validation failed: no valid sessionId found, removing malformed file\n"
    rm -f "$session_file"
    return 1
  fi

  log "Session validation passed: %s\n" "$session_file"
  return 0
}

has_any_sessions() {
  local project_dir
  project_dir=$(get_project_dir)

  if [ -d "$project_dir" ] && find "$project_dir" -maxdepth 1 -name "*.jsonl" -size +0c 2> /dev/null | grep -q .; then
    log "Sessions found in: %s\n" "$project_dir"
    return 0
  else
    log "No sessions found in: %s\n" "$project_dir"
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
    log "Resuming specified session: $ARG_RESUME_SESSION_ID"
    ARGS+=(--resume "$ARG_RESUME_SESSION_ID")
    [ "$ARG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ] && ARGS+=(--dangerously-skip-permissions)

  elif [ "$ARG_CONTINUE" = "true" ]; then

    if [ "$ARG_REPORT_TASKS" = "true" ]; then
      local session_file
      session_file=$(get_task_session_file)

      if task_session_exists && is_valid_session "$session_file"; then
        log "Resuming task session: $TASK_SESSION_ID"
        ARGS+=(--resume "$TASK_SESSION_ID" --dangerously-skip-permissions)
      else
        log "Starting new task session: $TASK_SESSION_ID"
        ARGS+=(--session-id "$TASK_SESSION_ID" --dangerously-skip-permissions)
        [ -n "$ARG_AI_PROMPT" ] && ARGS+=(-- "$ARG_AI_PROMPT")
      fi

    else
      if has_any_sessions; then
        log "Continuing most recent standalone session"
        ARGS+=(--continue)
        [ "$ARG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ] && ARGS+=(--dangerously-skip-permissions)
      else
        log "No sessions found, starting fresh standalone session"
        [ "$ARG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ] && ARGS+=(--dangerously-skip-permissions)
        [ -n "$ARG_AI_PROMPT" ] && ARGS+=(-- "$ARG_AI_PROMPT")
      fi
    fi

  else
    log "Continue disabled, starting fresh session"
    [ "$ARG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ] && ARGS+=(--dangerously-skip-permissions)
    [ -n "$ARG_AI_PROMPT" ] && ARGS+=(-- "$ARG_AI_PROMPT")
  fi

  log "Running claude code with args: %s\n" "$(printf '%q ' "${ARGS[@]}")"

  if [ "${ARG_ENABLE_BOUNDARY:-false}" = "true" ]; then
    install_boundary

    mkdir -p "$ARG_BOUNDARY_LOG_DIR"
    log "Starting with coder boundary enabled\n"

    # Build boundary args with conditional --unprivileged flag
    BOUNDARY_ARGS=(--log-dir "$ARG_BOUNDARY_LOG_DIR")
    # Add default allowed URLs
    BOUNDARY_ARGS+=(--allow "domain=anthropic.com" --allow "domain=registry.npmjs.org" --allow "domain=sentry.io" --allow "domain=claude.ai" --allow "domain=$ARG_CODER_HOST")

    # Add any additional allowed URLs from the variable
    if [[ -n "${ARG_BOUNDARY_ADDITIONAL_ALLOWED_URLS}" ]]; then
      IFS='|' read -ra ADDITIONAL_URLS <<< "${ARG_BOUNDARY_ADDITIONAL_ALLOWED_URLS}"
      for url in "${ADDITIONAL_URLS[@]}"; do
        # Quote the URL to preserve spaces within the allow rule
        BOUNDARY_ARGS+=(--allow "${url}")
      done
    fi

    # Set HTTP Proxy port used by Boundary
    BOUNDARY_ARGS+=(--proxy-port "${ARG_BOUNDARY_PROXY_PORT}")

    # Set log level for boundary
    BOUNDARY_ARGS+=(--log-level "${ARG_BOUNDARY_LOG_LEVEL}")

    if [[ "${ARG_ENABLE_BOUNDARY_PPROF:-false}" = "true" ]]; then
      # Enable boundary pprof server on specified port
      BOUNDARY_ARGS+=(--pprof)
      BOUNDARY_ARGS+=(--pprof-port "${ARG_BOUNDARY_PPROF_PORT}")
    fi

#    if [[ "${ARG_REPORT_TASKS}" == "true" ]]; then
#        boundary-run "${BOUNDARY_ARGS[@]}" -- \
#              claude "${ARGS[@]}"
#    else
      "${CORE_COMMAND[@]}" boundary-run "${BOUNDARY_ARGS[@]}" -- \
        claude "${ARGS[@]}"
#    fi
  else
    "${CORE_COMMAND[@]}" claude "${ARGS[@]}"
  fi
}

validate_claude_installation
start_agentapi
