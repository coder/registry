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
ARG_EXTERNAL_AUTH_ID=${ARG_EXTERNAL_AUTH_ID:-github}
ARG_RESUME_SESSION=${ARG_RESUME_SESSION:-true}

validate_copilot_installation() {
  if ! command_exists copilot; then
    echo "ERROR: Copilot CLI not installed. Run: npm install -g @github/copilot"
    exit 1
  fi
}

build_initial_prompt() {
  local initial_prompt=""

  if [ -n "$ARG_AI_PROMPT" ]; then
    if [ -n "$ARG_SYSTEM_PROMPT" ]; then
      initial_prompt="$ARG_SYSTEM_PROMPT

$ARG_AI_PROMPT"
    else
      initial_prompt="$ARG_AI_PROMPT"
    fi
  fi

  echo "$initial_prompt"
}

build_copilot_args() {
  COPILOT_ARGS=()

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

check_existing_session() {
  if [ "$ARG_RESUME_SESSION" = "true" ]; then
    if copilot --help > /dev/null 2>&1; then
      local session_dir="$HOME/.copilot/history-session-state"
      if [ -d "$session_dir" ] && [ -n "$(ls "$session_dir"/session_*_*.json 2> /dev/null)" ]; then
        local latest_session_file
        latest_session_file=$(ls "$session_dir"/session_*_*.json 2> /dev/null | sort -t_ -k3 -n -r | head -n 1)

        if [ -n "$latest_session_file" ]; then
          local session_id
          session_id=$(basename "$latest_session_file" | sed 's/session_\(.*\)_[0-9]*.json/\1/')

          if [ -n "$session_id" ]; then
            echo "Found existing Copilot CLI sessions. Will resume latest: $session_id"
            echo "$session_id"
            return 0
          fi
        fi
      fi
    fi
  fi
  echo ""
  return 1
}

setup_github_authentication() {
  echo "Setting up GitHub authentication..."

  if [ -n "${GITHUB_TOKEN:-}" ]; then
    export GH_TOKEN="$GITHUB_TOKEN"
    echo "✓ Using GitHub token from module configuration"
    return 0
  fi

  if command_exists coder; then
    local github_token
    if github_token=$(coder external-auth access-token "${ARG_EXTERNAL_AUTH_ID:-github}" 2> /dev/null); then
      if [ -n "$github_token" ] && [ "$github_token" != "null" ]; then
        export GITHUB_TOKEN="$github_token"
        export GH_TOKEN="$github_token"
        echo "✓ Using Coder external auth OAuth token"
        return 0
      fi
    fi
  fi

  if command_exists gh && gh auth status > /dev/null 2>&1; then
    echo "✓ Using GitHub CLI OAuth authentication"
    return 0
  fi

  echo "⚠ No GitHub authentication available"
  echo "  Copilot CLI will prompt for login during first use"
  echo "  Use the '/login' command in Copilot CLI to authenticate"
  return 0
}

start_agentapi() {
  echo "Starting in directory: $ARG_WORKDIR"
  cd "$ARG_WORKDIR"

  build_copilot_args

  local session_id
  session_id=$(check_existing_session)

  if [ -n "$session_id" ]; then
    echo "Resuming Copilot CLI session: $session_id"
    if [ ${#COPILOT_ARGS[@]} -gt 0 ]; then
      echo "Copilot arguments: ${COPILOT_ARGS[*]}"
      agentapi server --type copilot --term-width 120 --term-height 40 -- copilot --resume "$session_id" "${COPILOT_ARGS[@]}"
    else
      agentapi server --type copilot --term-width 120 --term-height 40 -- copilot --resume "$session_id"
    fi
  else
    echo "Starting new Copilot CLI session..."
    local initial_prompt
    initial_prompt=$(build_initial_prompt)

    if [ -n "$initial_prompt" ]; then
      echo "Using initial prompt with system context"
      if [ ${#COPILOT_ARGS[@]} -gt 0 ]; then
        echo "Copilot arguments: ${COPILOT_ARGS[*]}"
        agentapi server -I="$initial_prompt" --type copilot --term-width 120 --term-height 40 -- copilot "${COPILOT_ARGS[@]}"
      else
        agentapi server -I="$initial_prompt" --type copilot --term-width 120 --term-height 40 -- copilot
      fi
    else
      if [ ${#COPILOT_ARGS[@]} -gt 0 ]; then
        echo "Copilot arguments: ${COPILOT_ARGS[*]}"
        agentapi server --type copilot --term-width 120 --term-height 40 -- copilot "${COPILOT_ARGS[@]}"
      else
        agentapi server --type copilot --term-width 120 --term-height 40 -- copilot
      fi
    fi
  fi
}

setup_github_authentication
validate_copilot_installation
start_agentapi
