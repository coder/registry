#!/bin/bash
set -euo pipefail

source "$HOME"/.bashrc
export PATH="$HOME/.local/bin:$PATH"

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

ARG_WORKDIR=${ARG_WORKDIR:-"$HOME"}
ARG_AI_PROMPT=$(echo -n "${ARG_AI_PROMPT:-}" | base64 -d 2> /dev/null || echo "")
ARG_SYSTEM_PROMPT=$(echo -n "${ARG_SYSTEM_PROMPT:-}" | base64 -d 2> /dev/null || echo "")
ARG_COPILOT_MODEL=${ARG_COPILOT_MODEL:-}
ARG_ALLOW_ALL_TOOLS=${ARG_ALLOW_ALL_TOOLS:-false}
ARG_ALLOW_TOOLS=${ARG_ALLOW_TOOLS:-}
ARG_DENY_TOOLS=${ARG_DENY_TOOLS:-}
ARG_TRUSTED_DIRECTORIES=${ARG_TRUSTED_DIRECTORIES:-}

validate_copilot_installation() {
  if ! command_exists copilot; then
    echo "ERROR: Copilot CLI not installed. Run: npm install -g @github/copilot"
    exit 1
  fi
}

build_copilot_args() {
  COPILOT_ARGS=()

  # Combine system prompt with AI prompt if both exist
  if [ -n "$ARG_SYSTEM_PROMPT" ] && [ -n "$ARG_AI_PROMPT" ]; then
    local combined_prompt="$ARG_SYSTEM_PROMPT

Task: $ARG_AI_PROMPT"
    COPILOT_ARGS+=(--prompt "$combined_prompt")
  elif [ -n "$ARG_SYSTEM_PROMPT" ]; then
    COPILOT_ARGS+=(--prompt "$ARG_SYSTEM_PROMPT")
  elif [ -n "$ARG_AI_PROMPT" ]; then
    COPILOT_ARGS+=(--prompt "$ARG_AI_PROMPT")
  fi

  if [ "$ARG_ALLOW_ALL_TOOLS" = "true" ]; then
    COPILOT_ARGS+=(--allow-all-tools)
  fi

  if [ -n "$ARG_ALLOW_TOOLS" ]; then
    IFS=',' read -ra ALLOW_ARRAY <<< "$ARG_ALLOW_TOOLS"
    for tool in "${ALLOW_ARRAY[@]}"; do
      if [ -n "$tool" ]; then
        COPILOT_ARGS+=(--allow-tool "$tool")
      fi
    done
  fi

  if [ -n "$ARG_DENY_TOOLS" ]; then
    IFS=',' read -ra DENY_ARRAY <<< "$ARG_DENY_TOOLS"
    for tool in "${DENY_ARRAY[@]}"; do
      if [ -n "$tool" ]; then
        COPILOT_ARGS+=(--deny-tool "$tool")
      fi
    done
  fi
}

configure_copilot_model() {
  if [ -n "$ARG_COPILOT_MODEL" ]; then
    case "$ARG_COPILOT_MODEL" in
      "gpt-5")
        export COPILOT_MODEL="gpt-5"
        ;;
      "claude-sonnet-4")
        export COPILOT_MODEL="claude-sonnet-4"
        ;;
      "claude-sonnet-4.5")
        export COPILOT_MODEL="claude-sonnet-4.5"
        ;;
      *)
        echo "WARNING: Unknown model '$ARG_COPILOT_MODEL'. Using default."
        ;;
    esac
  fi
}

start_agentapi() {
  echo "Starting in directory: $ARG_WORKDIR"
  cd "$ARG_WORKDIR"

  build_copilot_args

  if [ ${#COPILOT_ARGS[@]} -gt 0 ]; then
    echo "Copilot arguments: ${COPILOT_ARGS[*]}"
    agentapi server --type claude --term-width 120 --term-height 40 -- copilot "${COPILOT_ARGS[@]}"
  else
    echo "Starting Copilot CLI in interactive mode"
    agentapi server --type claude --term-width 120 --term-height 40 -- copilot
  fi
}

configure_copilot_model

echo "COPILOT_MODEL=${ARG_COPILOT_MODEL:-${COPILOT_MODEL:-not set}}"
echo "GitHub authentication: via Coder external auth"

validate_copilot_installation
start_agentapi
