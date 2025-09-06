#!/bin/bash
set -euo pipefail

# Load user environment
# shellcheck source=/dev/null
source "$HOME/.bashrc"
# shellcheck source=/dev/null
if [ -f "$HOME/.nvm/nvm.sh" ]; then
  source "$HOME"/.nvm/nvm.sh
else
  export PATH="$HOME/.npm-global/bin:$PATH"
fi

function ensure_command() {
  command -v "$1" &> /dev/null || {
    echo "Error: '$1' not found." >&2
    exit 1
  }
}

ARG_AMP_START_DIRECTORY=${ARG_AMP_START_DIRECTORY:-"$HOME"}
ARG_AMP_API_KEY=${ARG_AMP_API_KEY:-}
ARG_AMP_TASK_PROMPT=$(echo -n "${ARG_AMP_TASK_PROMPT:-}" | base64 -d)
ARG_REPORT_TASKS=${ARG_REPORT_TASKS:-true}

echo "--------------------------------"
printf "API Key: %s\n" "$ARG_AMP_API_KEY"
printf "Workspace: %s\n" "$ARG_AMP_START_DIRECTORY"
printf "Task Prompt: %s\n" "$ARG_AMP_TASK_PROMPT"
printf "ARG_REPORT_TASKS: %s\n" "$ARG_REPORT_TASKS"
echo "--------------------------------"

ensure_command amp
echo "AMP version: $(amp --version)"

dir="$ARG_AMP_START_DIRECTORY"
if [[ -d "$dir" ]]; then
  echo "Using existing directory: $dir"
else
  echo "Creating directory: $dir"
  mkdir -p "$dir"
fi
cd "$dir"

if [ -n "$ARG_AMP_API_KEY" ]; then
  printf "amp_api_key provided !\n"
  export AMP_API_KEY=$ARG_AMP_API_KEY
else
  printf "amp_api_key not provided\n"
fi


if [ -n "$ARG_AMP_TASK_PROMPT" ]; then
  if [ "$ARG_REPORT_TASKS" == "true" ]; then
    printf "amp task prompt provided : %s" "$ARG_AMP_TASK_PROMPT\n"
    PROMPT="Every step of the way, report your progress using coder_report_task tool with proper summary and statuses. Your task at hand: $ARG_AMP_TASK_PROMPT"
  else
    PROMPT="$ARG_AMP_TASK_PROMPT"
  fi
  # Pipe the prompt into amp, which will be run inside agentapi
  agentapi server --type amp --term-width=67 --term-height=1190 -- bash -c "echo \"$PROMPT\" | amp"
else
  printf "No task prompt given.\n"
  agentapi server --type amp --term-width=67 --term-height=1190 -- amp
fi
