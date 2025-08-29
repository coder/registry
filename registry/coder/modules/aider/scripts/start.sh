#!/bin/bash
set -euo pipefail

# Ensure pipx-installed apps are in PATH
export PATH="$HOME/.local/bin:$PATH"

echo "--------------------------------"
echo "Provider: $ARG_AI_PROVIDER"
echo "Module: $ARG_AI_MODULE"
echo "--------------------------------"

ARG_TASK_PROMPT=$(echo -n "${ARG_TASK_PROMPT:-}" | base64 -d)

if [ -n "$ARG_API_KEY" ]; then
  printf "API key provided !\n"
  export $ARG_ENV_API_NAME_HOLDER=$ARG_API_KEY
else
  printf "API key not provided\n"
fi

if [[ "${AIDER_PROMPT}" == "true" && -n "${ARG_TASK_PROMPT:-}" ]]; then
  printf "Aider start only with this prompt : $ARG_TASK_PROMPT"
  mkdir -p $HOME/.aider-module/
  echo aider --model $ARG_AI_MODULE --yes-always --message "$ARG_TASK_PROMPT" > $HOME/.aider-module/aider_output.txt

elif [ -n "${ARG_TASK_PROMPT:-}" ]; then
  printf "Aider task prompt provided : $ARG_TASK_PROMPT"
  PROMPT="Every step of the way, report tasks to Coder with proper descriptions and statuses. Your task at hand: $ARG_TASK_PROMPT"

  agentapi server --term-width=67 --term-height=1190 -- aider --model $ARG_AI_MODULE --yes-always --message "$ARG_TASK_PROMPT"
else
  printf "No task prompt given.\n"
  agentapi server --term-width=67 --term-height=1190 -- aider --model $ARG_AI_MODULE --yes-always
fi
