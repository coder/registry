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
ARG_ENABLE_BOUNDARY=${ARG_ENABLE_BOUNDARY:-false}
ARG_BOUNDARY_VERSION=${ARG_BOUNDARY_VERSION:-"main"}
ARG_BOUNDARY_LOG_DIR=${ARG_BOUNDARY_LOG_DIR:-"/tmp/boundary_logs"}
ARG_BOUNDARY_LOG_LEVEL=${ARG_BOUNDARY_LOG_LEVEL:-"WARN"}
ARG_BOUNDARY_PROXY_PORT=${ARG_BOUNDARY_PROXY_PORT:-"8087"}
ARG_ENABLE_BOUNDARY_PPROF=${ARG_ENABLE_BOUNDARY_PPROF:-false}
ARG_BOUNDARY_PPROF_PORT=${ARG_BOUNDARY_PPROF_PORT:-"6067"}
ARG_CODER_HOST=${ARG_CODER_HOST:-}

echo "--------------------------------"

printf "ARG_MODEL: %s\n" "$ARG_MODEL"
printf "ARG_RESUME: %s\n" "$ARG_RESUME_SESSION_ID"
printf "ARG_CONTINUE: %s\n" "$ARG_CONTINUE"
printf "ARG_DANGEROUSLY_SKIP_PERMISSIONS: %s\n" "$ARG_DANGEROUSLY_SKIP_PERMISSIONS"
printf "ARG_PERMISSION_MODE: %s\n" "$ARG_PERMISSION_MODE"
printf "ARG_AI_PROMPT: %s\n" "$ARG_AI_PROMPT"
printf "ARG_WORKDIR: %s\n" "$ARG_WORKDIR"
printf "ARG_ENABLE_BOUNDARY: %s\n" "$ARG_ENABLE_BOUNDARY"
printf "ARG_BOUNDARY_VERSION: %s\n" "$ARG_BOUNDARY_VERSION"
printf "ARG_BOUNDARY_LOG_DIR: %s\n" "$ARG_BOUNDARY_LOG_DIR"
printf "ARG_BOUNDARY_LOG_LEVEL: %s\n" "$ARG_BOUNDARY_LOG_LEVEL"
printf "ARG_BOUNDARY_PROXY_PORT: %s\n" "$ARG_BOUNDARY_PROXY_PORT"
printf "ARG_CODER_HOST: %s\n" "$ARG_CODER_HOST"

echo "--------------------------------"

# see the remove-last-session-id.sh script for details
# about why we need it
# avoid exiting if the script fails
bash "/tmp/remove-last-session-id.sh" "$(pwd)" 2> /dev/null || true

function install_boundary() {
  # Install boundary from public github repo
  git clone https://github.com/coder/boundary
  cd boundary
  git checkout $ARG_BOUNDARY_VERSION
  go install ./cmd/...
}

function validate_claude_installation() {
  if command_exists claude; then
    printf "Claude Code is installed\n"
  else
    printf "Error: Claude Code is not installed. Please enable install_claude_code or install it manually\n"
    exit 1
  fi
}

TASK_SESSION_ID="cd32e253-ca16-4fd3-9825-d837e74ae3c2"

task_session_exists() {
  if find "$HOME/.claude" -type f -name "*${TASK_SESSION_ID}*" 2> /dev/null | grep -q .; then
    return 0
  else
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
    echo "Using explicit resume_session_id: $ARG_RESUME_SESSION_ID"
    ARGS+=(--resume "$ARG_RESUME_SESSION_ID")
    if [ "$ARG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ]; then
      ARGS+=(--dangerously-skip-permissions)
    fi
  elif [ "$ARG_CONTINUE" = "true" ]; then
    if task_session_exists; then
      echo "Task session detected (ID: $TASK_SESSION_ID)"
      ARGS+=(--resume "$TASK_SESSION_ID")
      if [ "$ARG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ]; then
        ARGS+=(--dangerously-skip-permissions)
      fi
      echo "Resuming existing task session"
    else
      echo "No existing task session found"
      ARGS+=(--session-id "$TASK_SESSION_ID")
      if [ -n "$ARG_AI_PROMPT" ]; then
        ARGS+=(--dangerously-skip-permissions "$ARG_AI_PROMPT")
        echo "Starting new task session with prompt"
      else
        if [ "$ARG_DANGEROUSLY_SKIP_PERMISSIONS" = "true" ]; then
          ARGS+=(--dangerously-skip-permissions)
        fi
        echo "Starting new task session"
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

  if [ "${ARG_ENABLE_BOUNDARY:-false}" = "true" ]; then
    install_boundary

    mkdir -p "$ARG_BOUNDARY_LOG_DIR"
    printf "Starting with coder boundary enabled\n"

    # Build boundary args with conditional --unprivileged flag
    BOUNDARY_ARGS=(--log-dir "$ARG_BOUNDARY_LOG_DIR")
    # Add default allowed URLs
    BOUNDARY_ARGS+=(--allow "*anthropic.com" --allow "registry.npmjs.org" --allow "*sentry.io" --allow "claude.ai" --allow "$ARG_CODER_HOST")

    # Add any additional allowed URLs from the variable
    if [ -n "$ARG_BOUNDARY_ADDITIONAL_ALLOWED_URLS" ]; then
      IFS=' ' read -ra ADDITIONAL_URLS <<< "$ARG_BOUNDARY_ADDITIONAL_ALLOWED_URLS"
      for url in "${ADDITIONAL_URLS[@]}"; do
        BOUNDARY_ARGS+=(--allow "$url")
      done
    fi

    # Set HTTP Proxy port used by Boundary
    BOUNDARY_ARGS+=(--proxy-port "$ARG_BOUNDARY_PROXY_PORT")

    # Set log level for boundary
    BOUNDARY_ARGS+=(--log-level "$ARG_BOUNDARY_LOG_LEVEL")

    if [ "${ARG_ENABLE_BOUNDARY_PPROF:-false}" = "true" ]; then
      # Enable boundary pprof server on specified port
      BOUNDARY_ARGS+=(--pprof)
      BOUNDARY_ARGS+=(--pprof-port "$ARG_BOUNDARY_PPROF_PORT")
    fi

    agentapi server --allowed-hosts="*" --type claude --term-width 67 --term-height 1190 -- \
      sudo -E env PATH="$PATH" setpriv --reuid="$(id -u)" --regid="$(id -g)" --clear-groups \
      --inh-caps=+net_admin --ambient-caps=+net_admin --bounding-set=+net_admin boundary "${BOUNDARY_ARGS[@]}" -- \
      claude "${ARGS[@]}"
  else
    agentapi server --type claude --term-width 67 --term-height 1190 -- claude "${ARGS[@]}"
  fi
}

validate_claude_installation
start_agentapi
