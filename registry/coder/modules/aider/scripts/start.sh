#!/bin/bash
set -euo pipefail

# Ensure pipx-installed apps are in PATH
export PATH="$HOME/.local/bin:$PATH"

echo "--------------------------------"
echo "Provider: $ARG_AI_PROVIDER"
echo "Module: $ARG_AI_MODULE"
echo "--------------------------------"

if [ -n "$ARG_API_KEY" ]; then
  printf "API key provided !\n"
  export $ARG_ENV_API_NAME_HOLDER=$ARG_API_KEY
else
  printf "API key not provided\n"
fi




if [ -n "${AIDER_TASK_PROMPT:-}" ]; then
  printf "Aider task prompt provided : $AIDER_TASK_PROMPT"
  PROMPT="Every step of the way, report tasks to Coder with proper descriptions and statuses. Your task at hand: $AIDER_TASK_PROMPT"

  # Pipe the prompt into amp, which will be run inside agentapi
  agentapi server --term-width=67 --term-height=1190 -- aider --model $ARG_AI_MODULE --message "$AIDER_TASK_PROMPT"
else
  printf "No task prompt given.\n"
  agentapi server --term-width=67 --term-height=1190 -- aider --model $ARG_AI_MODULE
fi