#!/bin/bash
set -euo pipefail

export PATH=/home/coder/.opencode/bin:$PATH

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

ARG_WORKDIR=${ARG_WORKDIR:-"$HOME"}
ARG_AI_PROMPT=$(echo -n "${ARG_AI_PROMPT:-}" | base64 -d 2> /dev/null || echo "")
ARG_REPORT_TASKS=${ARG_REPORT_TASKS:-true}
ARG_MODEL=${ARG_MODEL:-}
ARG_AGENT=${ARG_AGENT:-}
ARG_SESSION_ID=${ARG_SESSION_ID:-}
ARG_CONTINUE=${ARG_CONTINUE:-false}

# Print all received environment variables
printf "=== START CONFIG ===\n"
printf "ARG_WORKDIR: %s\n" "$ARG_WORKDIR"
printf "ARG_REPORT_TASKS: %s\n" "$ARG_REPORT_TASKS"
printf "ARG_MODEL: %s\n" "$ARG_MODEL"
printf "ARG_AGENT: %s\n" "$ARG_AGENT"
printf "ARG_CONTINUE: %s\n" "$ARG_CONTINUE"
printf "ARG_SESSION_ID: %s\n" "$ARG_SESSION_ID"
if [ -n "$ARG_AI_PROMPT" ]; then
  printf "ARG_AI_PROMPT: [AI PROMPT RECEIVED]\n"
else
  printf "ARG_AI_PROMPT: [NOT PROVIDED]\n"
fi
printf "==================================\n"

OPENCODE_ARGS=()


validate_opencode_installation() {
  if ! command_exists opencode; then
    printf "ERROR: OpenCode not installed. Set install_opencode to true\n"
    exit 1
  fi
}

build_opencode_args() {
  if [ -n "$ARG_MODEL" ]; then
    OPENCODE_ARGS+=(--model "$ARG_MODEL")
  fi

  if [ -n "$ARG_AGENT" ]; then
    OPENCODE_ARGS+=(--agent "$ARG_AGENT")
  fi

  if [ -n "$ARG_SESSION_ID" ]; then
    OPENCODE_ARGS+=(--session "$ARG_SESSION_ID")
  fi

  if [ "$ARG_CONTINUE" = "true" ]; then
    OPENCODE_ARGS+=(--continue)
  fi

  if [ -n "$ARG_AI_PROMPT" ]; then
    if [ "$ARG_REPORT_TASKS" = "true" ]; then
      PROMPT="Every step of the way, report your progress using coder_report_task tool with proper summary and statuses. Your task at hand: $ARG_AI_PROMPT"
    else
      PROMPT="$ARG_AI_PROMPT"
    fi
    OPENCODE_ARGS+=(--prompt "$PROMPT")
  fi
}

start_agentapi() {
  printf "Starting in directory: %s\n" "$ARG_WORKDIR"
  cd "$ARG_WORKDIR"

  build_opencode_args

  printf "Running OpenCode with args: %s\n" "${OPENCODE_ARGS[*]}"
  agentapi server --type opencode --term-width 67 --term-height 1190 -- opencode "${OPENCODE_ARGS[@]}"
}

validate_opencode_installation
start_agentapi