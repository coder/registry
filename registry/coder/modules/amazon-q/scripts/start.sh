#!/bin/bash
# Start script for amazon-q module

set -o errexit
set -o pipefail

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

# Decode inputs
ARG_AI_PROMPT=$(echo -n "${ARG_AI_PROMPT:-}" | base64 -d)
ARG_TRUST_ALL_TOOLS=${ARG_TRUST_ALL_TOOLS:-true}
ARG_MODULE_DIR_NAME=${ARG_MODULE_DIR_NAME:-.aws/amazonq}
ARG_WORKDIR=${ARG_WORKDIR:-"$HOME"}
ARG_REPORT_TASKS=${ARG_REPORT_TASKS:-true}
ARG_SERVER_PARAMETERS=${ARG_SERVER_PARAMETERS:-""}

echo "--------------------------------"
echo "ai_prompt: $ARG_AI_PROMPT"
echo "trust_all_tools: $ARG_TRUST_ALL_TOOLS"
echo "module_dir_name: $ARG_MODULE_DIR_NAME"
echo "workdir: $ARG_WORKDIR"
echo "report_tasks: ${ARG_REPORT_TASKS}"
echo "--------------------------------"

mkdir -p "$HOME/$ARG_MODULE_DIR_NAME"

# Find Amazon Q CLI
if command_exists q; then
  Q_CMD=q
elif [ -x "$HOME/.local/bin/q" ]; then
  Q_CMD="$HOME/.local/bin/q"
else
  echo "Error: Amazon Q CLI not found. Install it or set install_amazon_q=true."
  exit 1
fi

mkdir -p "$ARG_WORKDIR"
cd "$ARG_WORKDIR"

# Set up environment
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# Build command arguments
ARGS=(chat)

if [ "$ARG_TRUST_ALL_TOOLS" = "true" ]; then
  ARGS+=(--trust-all-tools)
fi

# Log and run with agentapi integration
printf "Running: %q %s\n" "$Q_CMD" "$(printf '%q ' "${ARGS[@]}")"

# If we have an AI prompt, we need to handle it specially
if [ -n "$ARG_AI_PROMPT" ]; then
  if [ "$ARG_REPORT_TASKS" == "true" ]; then
    PROMPT="Every step of the way, report your progress using coder_report_task tool with proper summary and statuses. Your task at hand: $ARG_AI_PROMPT"
  else
    PROMPT="$ARG_AI_PROMPT"
  fi
  ARGS+=("$PROMPT")
fi

# Use agentapi to manage the interactive session with initial prompt
agentapi server ${ARG_SERVER_PARAMETERS} --term-width 67 --term-height 1190 -- "$Q_CMD" "${ARGS[@]}"
