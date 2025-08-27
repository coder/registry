#!/bin/bash
set -euo pipefail

source "$HOME"/.bashrc

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

if [ -f "$HOME/.nvm/nvm.sh" ]; then
  source "$HOME"/.nvm/nvm.sh
else
  export PATH="$HOME/.npm-global/bin:$PATH"
fi

ARG_AUGGIE_START_DIRECTORY=${ARG_AUGGIE_START_DIRECTORY:-"$HOME"}
ARG_TASK_PROMPT=$(echo -n "${ARG_TASK_PROMPT:-}" | base64 -d)
ARG_MCP_FILES=${ARG_MCP_FILES:-[]}
ARG_AUGGIE_RULES=${ARG_AUGGIE_RULES:-}
ARG_AUGMENT_SESSION_AUTH=${ARG_AUGMENT_SESSION_AUTH:-}
ARG_AUGGIE_CONTINUE_PREVIOUS_CONVERSATION=${ARG_AUGGIE_CONTINUE_PREVIOUS_CONVERSATION:-false}
ARG_AUGGIE_INTERACTION_MODE=${ARG_AUGGIE_INTERACTION_MODE:-"interactive"}
ARG_AUGGIE_MODEL=${ARG_AUGGIE_MODEL:-}
ARG_REPORT_TASKS=${ARG_REPORT_TASKS:-false}

ARGS=()

echo "--------------------------------"

printf "auggie_start_directory: %s\n" "$ARG_AUGGIE_START_DIRECTORY"
printf "task_prompt: %s\n" "$ARG_TASK_PROMPT"
printf "mcp_files: %s\n" "$ARG_MCP_FILES"
printf "auggie_rules: %s\n" "$ARG_AUGGIE_RULES"
printf "continue_previous_conversation: %s\n" "$ARG_AUGGIE_CONTINUE_PREVIOUS_CONVERSATION"
printf "auggie_interaction_mode: %s\n" "$ARG_AUGGIE_INTERACTION_MODE"
printf "augment_session_auth: %s\n" "$ARG_AUGMENT_SESSION_AUTH"
printf "auggie_model: %s\n" "$ARG_AUGGIE_MODEL"
printf "report_tasks: %s\n" "$ARG_REPORT_TASKS"

echo "--------------------------------"

function validate_auggie_installation() {
  if command_exists auggie; then
    printf "Auggie is installed\n"
  else
    printf "Error: Auggie is not installed. Please enable install_auggie or install it manually\n"
    exit 1
  fi
}

function build_auggie_args() {
  if [ -n "$ARG_AUGGIE_INTERACTION_MODE" ]; then
    if [ "$ARG_AUGGIE_INTERACTION_MODE" != "interactive" ]; then
      ARGS+=(--"$ARG_AUGGIE_INTERACTION_MODE")
    fi
  fi

  if [ -n "$ARG_AUGGIE_MODEL" ]; then
    ARGS+=(--model "$ARG_AUGGIE_MODEL")
  fi

  if [ -f "$HOME/.augment/user_mcp.json" ]; then
    ARGS+=(--mcp-config "$HOME/.augment/user_mcp.json")
  fi

  if [ -n "$ARG_MCP_FILES" ] && [ "$ARG_MCP_FILES" != "[]" ]; then
    for file in $(echo "$ARG_MCP_FILES" | jq -r '.[]'); do
      ARGS+=(--mcp-config "$file")
    done
  fi

  ARGS+=(--mcp-config "$HOME/.augment/coder_mcp.json")

  if [ -n "$ARG_AUGGIE_RULES" ]; then
    AUGGIE_RULES_FILE="$HOME/.augment/rules.md"
    ARGS+=(--rules "$AUGGIE_RULES_FILE")
  fi

  if [ "$ARG_AUGGIE_CONTINUE_PREVIOUS_CONVERSATION" == "true" ]; then
    ARGS+=(--continue)
  fi

  if [ -n "$ARG_TASK_PROMPT" ]; then
    if [ "$ARG_REPORT_TASKS" == "true" ]; then
      PROMPT="Every step of the way, report your progress using coder_report_task tool with proper summary and statuses. Your task at hand: $ARG_TASK_PROMPT"
    else
      PROMPT="$ARG_TASK_PROMPT"
    fi
    ARGS+=(--instruction "$PROMPT")
  fi
}

function start_agentapi_server() {
  mkdir -p "$ARG_AUGGIE_START_DIRECTORY"
  cd "$ARG_AUGGIE_START_DIRECTORY"
  ARGS+=(--workspace-root "$ARG_AUGGIE_START_DIRECTORY")
  printf "Running auggie with args: %s\n" "$(printf '%q ' "${ARGS[@]}")"
  agentapi server --term-width 67 --term-height 1190 -- auggie "${ARGS[@]}"
}

validate_auggie_installation
build_auggie_args
start_agentapi_server
