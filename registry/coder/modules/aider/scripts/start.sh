#!/bin/bash
set -euo pipefail

# Ensure pipx-installed apps are in PATH
export PATH="$HOME/.local/bin:$PATH"

source "$HOME/.bashrc"
# shellcheck source=/dev/null
if [ -f "$HOME/.nvm/nvm.sh" ]; then
  source "$HOME"/.nvm/nvm.sh
else
  export PATH="$HOME/.npm-global/bin:$PATH"
fi


ARG_WORKDIR=${ARG_WORKDIR:-/home/coder}
ARG_API_KEY=$(echo -n "${ARG_API_KEY:-}" | base64 -d)
ARG_SYSTEM_PROMPT=$(echo -n "${ARG_SYSTEM_PROMPT:-}" | base64 -d 2> /dev/null || echo "")
ARG_AI_PROMPT=$(echo -n "${ARG_AI_PROMPT:-}" | base64 -d 2> /dev/null || echo "")
ARG_MODEL=${ARG_MODEL:-}
ARG_PROVIDER=${ARG_PROVIDER:-}
ARG_ENV_API_NAME_HOLDER=${ARG_ENV_API_NAME_HOLDER:-}

echo "--------------------------------"
echo "Provider: $ARG_PROVIDER"
echo "Module: $ARG_MODEL"
echo "--------------------------------"

if [ -n "$ARG_API_KEY" ]; then
  printf "API key provided !\n"
  export $ARG_ENV_API_NAME_HOLDER=$ARG_API_KEY
else
  printf "API key not provided\n"
fi

function build_initial_prompt() {
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

function start_agentapi() {
  echo "Starting agentAPI in directory: $ARG_WORKDIR"
  cd "$ARG_WORKDIR"
  touch ".aider.model.settings.yml"
  echo "- name: $ARG_MODEL
    extra_params:
      api_key: $ARG_API_KEY
      api_base: http://localhost:8000/v1/" > "./.aider.model.settings.yml"
  agentapi server --term-width=67 --term-height=1190 -- aider --model $ARG_MODEL --yes-always
}

function start_mcpm_aider_bridge_bg() {
  echo "Starting mcpm-aider bridge in background..."

  # directory for logs/pid
  LOG_DIR="${ARG_WORKDIR:-.}/logs"
  mkdir -p "$LOG_DIR"

  TIMESTAMP=$(date +'%Y%m%d-%H%M%S')
  LOG_FILE="$LOG_DIR/mcpm-aider.$TIMESTAMP.log"
  PID_FILE="$LOG_DIR/mcpm-aider.pid"

  # tool list
  printf "mcpm-aider tool list" "$(mcpm-aider list)"
  # start detached with nohup, capture PID
  nohup mcpm-aider start-bridge --server https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent >> "$LOG_FILE" 2>&1 &
  MC_PM_PID=$!
  echo "$MC_PM_PID" > "$PID_FILE"

  # simple health check: ensure process started
  sleep 1
  if kill -0 "$MC_PM_PID" 2>/dev/null; then
    echo "mcpm-aider started (pid $MC_PM_PID). Logs: $LOG_FILE"
  else
    echo "mcpm-aider failed to start. Check $LOG_FILE" >&2
    # optional: exit here if you want to abort
    # exit 1
  fi

  # optional: when this script exits before agentapi finishes, kill background
  # (If you want mcpm-aider to keep running after agentapi exits, remove this trap.)
  trap 'echo "Stopping background mcpm-aider (pid $MC_PM_PID)"; kill "$MC_PM_PID" 2>/dev/null || true' EXIT
}



# function start_agentapi() {
#   echo "Starting in directory: $ARG_WORKDIR"
#   cd "$ARG_WORKDIR"

#   local initial_prompt
#   initial_prompt=$(build_initial_prompt)
#   if [ -n "$initial_prompt" ]; then
#     echo "Using Initial Prompt to Start agentapi with Task Prompt"
#     agentapi server -I="$initial_prompt" --type aider --term-width=67 --term-height=1190 -- aider --model $ARG_MODEL --yes-always
#   else
#     agentapi server --term-width=67 --term-height=1190 -- aider --model $ARG_MODEL --yes-always
#   fi 
# }



start_mcpm_aider_bridge_bg
start_agentapi