#!/bin/bash

if [ -f "$HOME/.bashrc" ]; then
  source "$HOME"/.bashrc
fi

set -euo pipefail

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
ARG_ENABLE_AIBRIDGE_PROXY=${ARG_ENABLE_AIBRIDGE_PROXY:-false}
ARG_AIBRIDGE_PROXY_AUTH_URL=${ARG_AIBRIDGE_PROXY_AUTH_URL:-}
ARG_AIBRIDGE_PROXY_CERT_PATH=${ARG_AIBRIDGE_PROXY_CERT_PATH:-}

validate_copilot_installation() {
  if ! command_exists copilot; then
    echo "ERROR: Copilot not installed. Run: npm install -g @github/copilot"
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
        echo "Found existing Copilot session. Will continue latest session." >&2
        return 0
      fi
    fi
  fi
  return 1
}

setup_github_authentication() {
  export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
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
  echo "  Copilot will prompt for login during first use"
  echo "  Use the '/login' command in Copilot to authenticate"
  return 0
}

setup_aibridge_proxy() {
  if [ "$ARG_ENABLE_AIBRIDGE_PROXY" != "true" ]; then
    return 0
  fi

  echo "Setting up AI Bridge Proxy..."

  # Wait for the aibridge-proxy module to finish.
  # Uses startup coordination to block until aibridge-proxy-setup signals completion.
  if command -v coder > /dev/null 2>&1; then
    coder exp sync want "copilot-aibridge" "aibridge-proxy-setup" || true
    coder exp sync start "copilot-aibridge" || true
    trap 'coder exp sync complete "copilot-aibridge" > /dev/null 2>&1 || true' EXIT
  fi

  if [ -z "$ARG_AIBRIDGE_PROXY_AUTH_URL" ]; then
    echo "ERROR: AI Bridge Proxy is enabled but no proxy auth URL provided."
    exit 1
  fi

  if [ -z "$ARG_AIBRIDGE_PROXY_CERT_PATH" ]; then
    echo "ERROR: AI Bridge Proxy is enabled but no certificate path provided."
    exit 1
  fi

  if [ ! -f "$ARG_AIBRIDGE_PROXY_CERT_PATH" ]; then
    echo "ERROR: AI Bridge Proxy certificate not found at $ARG_AIBRIDGE_PROXY_CERT_PATH."
    echo "  Ensure the aibridge-proxy module has successfully completed setup."
    exit 1
  fi

  # Set proxy environment variables scoped to this process tree only.
  # These are inherited by the agentapi/copilot process below,
  # but do not affect other workspace processes, avoiding routing
  # unnecessary traffic through the proxy.
  export HTTPS_PROXY="$ARG_AIBRIDGE_PROXY_AUTH_URL"
  export NODE_EXTRA_CA_CERTS="$ARG_AIBRIDGE_PROXY_CERT_PATH"

  echo "✓ AI Bridge Proxy configured"
  echo "  CA certificate: $ARG_AIBRIDGE_PROXY_CERT_PATH"
}

start_agentapi() {
  echo "Starting in directory: $ARG_WORKDIR"
  cd "$ARG_WORKDIR"

  build_copilot_args

  if check_existing_session; then
    echo "Continuing latest Copilot session..."
    if [ ${#COPILOT_ARGS[@]} -gt 0 ]; then
      echo "Copilot arguments: ${COPILOT_ARGS[*]}"
      agentapi server --type copilot --term-width 120 --term-height 40 -- copilot --continue "${COPILOT_ARGS[@]}"
    else
      agentapi server --type copilot --term-width 120 --term-height 40 -- copilot --continue
    fi
  else
    echo "Starting new Copilot session..."
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
setup_aibridge_proxy
validate_copilot_installation
start_agentapi
