#!/bin/bash
set -euo pipefail

# Ensure pipx-installed apps are in PATH
export PATH="$HOME/.local/bin:$PATH"

ARG_WORKDIR=${ARG_WORKDIR:-/home/coder}
ARG_API_KEY=$(echo -n "${ARG_API_KEY:-}" | base64 -d)
ARG_SYSTEM_PROMPT=$(echo -n "${ARG_SYSTEM_PROMPT:-}" | base64 -d 2> /dev/null || echo "")
ARG_AI_PROMPT=$(echo -n "${ARG_AI_PROMPT:-}" | base64 -d 2> /dev/null || echo "")
ARG_MODEL=${ARG_MODEL:-}
ARG_PROVIDER=${ARG_PROVIDER:-}
ARG_ENV_API_NAME_HOLDER=${ARG_ENV_API_NAME_HOLDER:-}

echo "--------------------------------"
echo "Provider: $ARG_PROVIDER"
echo "Model: $ARG_MODEL"
echo "--------------------------------"

if [ -n "$ARG_API_KEY" ]; then
  printf "API key provided!\n"
  export $ARG_ENV_API_NAME_HOLDER=$ARG_API_KEY
 else
  printf "API key not provided.\n"
 fi

build_initial_prompt() {
  local initial_prompt=""
  if [ -n "$ARG_AI_PROMPT" ]; then
    if [ -n "$ARG_SYSTEM_PROMPT" ]; then
      initial_prompt="$ARG_SYSTEM_PROMPT $ARG_AI_PROMPT"
    else
      initial_prompt="$ARG_AI_PROMPT"
    fi
  fi
  echo "$initial_prompt"
}

start_agentapi() {
  echo "Starting in directory: $ARG_WORKDIR"
  cd "$ARG_WORKDIR"

  local initial_prompt
  initial_prompt=$(build_initial_prompt)
  if [ -n "$initial_prompt" ]; then
    echo "Starting agentapi with initial prompt"
    agentapi server -I="$initial_prompt" --type aider --term-width=67 --term-height=1190 -- aider --model $ARG_MODEL --yes-always
  else
    agentapi server --term-width=67 --term-height=1190 -- aider --model $ARG_MODEL --yes-always
  fi
}

# TODO: Implement MCP server for coder when Aider support MCP servers.

start_agentapi
