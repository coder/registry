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

ARG_SOURCEGRAPH_AMP_START_DIRECTORY=${ARG_SOURCEGRAPH_AMP_START_DIRECTORY:-"$HOME"}
ARG_SOURCEGRAPH_AMP_API_KEY=${ARG_SOURCEGRAPH_AMP_API_KEY:-}
ARG_SOURCEGRAPH_AMP_TASK_PROMPT=${ARG_SOURCEGRAPH_AMP_TASK_PROMPT:-}

echo "--------------------------------"
printf "API Key: %s\n" "$ARG_SOURCEGRAPH_AMP_API_KEY"
printf "Workspace: %s\n" "$ARG_SOURCEGRAPH_AMP_START_DIRECTORY"
printf "Task Prompt: %s\n" "$ARG_SOURCEGRAPH_AMP_TASK_PROMPT"
echo "--------------------------------"

ensure_command amp
echo "AMP version: $(amp --version)"

dir="$ARG_SOURCEGRAPH_AMP_START_DIRECTORY"
if [[ -d "$dir" ]]; then
  echo "Using existing directory: $dir"
else
  echo "Creating directory: $dir"
  mkdir -p "$dir"
fi
cd "$dir"

if [ -n "$ARG_SOURCEGRAPH_AMP_API_KEY" ]; then
  printf "sourcegraph_amp_api_key provided !\n"
  export AMP_API_KEY=$ARG_SOURCEGRAPH_AMP_API_KEY
else
  printf "sourcegraph_amp_api_key not provided\n"
fi

if [ -n "${ARG_SOURCEGRAPH_AMP_TASK_PROMPT:-}" ]; then
  printf "sourcegraph amp task prompt provided : %s" "$ARG_SOURCEGRAPH_AMP_TASK_PROMPT"
  PROMPT="Every step of the way, report tasks to Coder with proper descriptions and statuses. Your task at hand: $ARG_SOURCEGRAPH_AMP_TASK_PROMPT"

  # Pipe the prompt into amp, which will be run inside agentapi
  agentapi server --type amp --term-width=67 --term-height=1190 -- bash -c "echo \"$PROMPT\" | amp"
else
  printf "No task prompt given.\n"
  agentapi server --type amp --term-width=67 --term-height=1190 -- amp
fi
