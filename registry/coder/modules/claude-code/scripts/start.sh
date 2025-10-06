#!/bin/bash
set -euo pipefail

source "$HOME"/.bashrc
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
ARG_BOUNDARY_LOG_DIR=${ARG_BOUNDARY_LOG_DIR:-"/tmp/boundary_logs"}
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
printf "ARG_BOUNDARY_LOG_DIR: %s\n" "$ARG_BOUNDARY_LOG_DIR"
printf "ARG_CODER_HOST: %s\n" "$ARG_CODER_HOST"

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

ARGS=()

function build_claude_args() {
  if [ -n "$ARG_MODEL" ]; then
    ARGS+=(--model "$ARG_MODEL")
  fi

  if [ -n "$ARG_RESUME_SESSION_ID" ]; then
    ARGS+=(--resume "$ARG_RESUME_SESSION_ID")
  fi

  if [ "$ARG_CONTINUE" = "true" ]; then
    ARGS+=(--continue)
  fi

  if [ -n "$ARG_PERMISSION_MODE" ]; then
    ARGS+=(--permission-mode "$ARG_PERMISSION_MODE")
  fi

}

function start_agentapi() {
  mkdir -p "$ARG_WORKDIR"
  cd "$ARG_WORKDIR"
  if [ -n "$ARG_AI_PROMPT" ]; then
    ARGS+=(--dangerously-skip-permissions "$ARG_AI_PROMPT")
  else
    if [ -n "$ARG_DANGEROUSLY_SKIP_PERMISSIONS" ]; then
      ARGS+=(--dangerously-skip-permissions)
    fi
  fi
  printf "Running claude code with args: %s\n" "$(printf '%q ' "${ARGS[@]}")"

  if [ "${ARG_ENABLE_BOUNDARY:-false}" = "true" ]; then
    mkdir -p "$ARG_BOUNDARY_LOG_DIR"
    printf "Starting with coder boundary enabled\n"
    agentapi server --type claude --term-width 67 --term-height 1190 -- \
      coder boundary --log-dir "$ARG_BOUNDARY_LOG_DIR" \
      --allow "*.anthropic.com" --allow "$ARG_CODER_HOST" -- \
      claude "${ARGS[@]}"
  else
    agentapi server --type claude --term-width 67 --term-height 1190 -- claude "${ARGS[@]}"
  fi
}

validate_claude_installation
build_claude_args
start_agentapi
