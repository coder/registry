#!/bin/bash
set -euo pipefail

# Ensure pipx-installed apps are in PATH
export PATH="$HOME/.local/bin:$PATH"

AIDER_START_DIRECTORY=${AIDER_START_DIRECTORY:-/home/coder}
ARG_API_KEY=$(echo -n "${ARG_API_KEY:-}" | base64 -d)
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

# if [[ "${AIDER_PROMPT}" == "true" && -n "${ARG_AI_PROMPT:-}" ]]; then
#   printf "Aider start only with this prompt : $ARG_AI_PROMPT"
#   mkdir -p $HOME/.aider-module/
#   echo aider --model $ARG_MODEL --yes-always --message "$ARG_AI_PROMPT" > $HOME/.aider-module/aider_output.txt

if [ -n "${ARG_AI_PROMPT:-}" ]; then
  printf "Aider task prompt provided : $ARG_AI_PROMPT"
  PROMPT="Every step of the way, report tasks to Coder with proper descriptions and statuses. Your task at hand: $ARG_AI_PROMPT"

  agentapi server --term-width=67 --term-height=1190 -- aider --model $ARG_MODEL --yes-always --message "$ARG_AI_PROMPT"
else
  printf "No task prompt given.\n"
  agentapi server --term-width=67 --term-height=1190 -- aider --model $ARG_MODEL --yes-always
fi
