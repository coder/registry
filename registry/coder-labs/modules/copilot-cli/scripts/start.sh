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

setup_github_authentication() {
  echo "Setting up GitHub authentication..."

  # Check for provided token first (highest priority)
  if [ -n "$GITHUB_TOKEN" ]; then
    export GH_TOKEN="$GITHUB_TOKEN"
    echo "✓ Using GitHub token from module configuration"
    return 0
  fi

  # Try external auth
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

  # Try GitHub CLI as fallback
  if command_exists gh && gh auth status > /dev/null 2>&1; then
    echo "✓ Using GitHub CLI OAuth authentication"
    return 0
  fi

  echo "⚠ No GitHub authentication available"
  echo "  Copilot CLI will prompt for login during first use"
  echo "  Use the '/login' command in Copilot CLI to authenticate"
  return 0 # Don't fail - let Copilot CLI handle authentication
}

start_agentapi() {
  echo "Starting in directory: $ARG_WORKDIR"
  cd "$ARG_WORKDIR"

  build_copilot_args

  local mcp_args=()
  local module_path="$HOME/.copilot-module"

  if [ -f "$module_path/mcp_config.json" ]; then
    mcp_args+=(--mcp-config "$module_path/mcp_config.json")
  fi

  if [ ${#COPILOT_ARGS[@]} -gt 0 ]; then
    echo "Copilot arguments: ${COPILOT_ARGS[*]}"
    if [ ${#mcp_args[@]} -gt 0 ]; then
      agentapi server --type claude --term-width 120 --term-height 40 "${mcp_args[@]}" -- copilot "${COPILOT_ARGS[@]}"
    else
      agentapi server --type claude --term-width 120 --term-height 40 -- copilot "${COPILOT_ARGS[@]}"
    fi
  else
    if [ ${#mcp_args[@]} -gt 0 ]; then
      agentapi server --type claude --term-width 120 --term-height 40 "${mcp_args[@]}" -- copilot
    else
      agentapi server --type claude --term-width 120 --term-height 40 -- copilot
    fi
  fi
}

configure_copilot_model

echo "COPILOT_MODEL=${ARG_COPILOT_MODEL:-${COPILOT_MODEL:-not set}}"

setup_github_authentication
validate_copilot_installation
start_agentapi
