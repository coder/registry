#!/bin/bash

source "$HOME"/.bashrc
set -o errexit
set -o pipefail
command_exists() {
  command -v "$1" > /dev/null 2>&1
}

if [ -f "$HOME/.nvm/nvm.sh" ]; then
  source "$HOME"/.nvm/nvm.sh
else
  export PATH="$HOME/.npm-global/bin:$PATH"
fi

printf "Version: %s\n" "$(codex --version)"
set -o nounset
ARG_CODEX_TASK_PROMPT=$(echo -n "$ARG_CODEX_TASK_PROMPT" | base64 -d)

echo "=== Codex Launch Configuration ==="
printf "OpenAI API Key: %s\n" "$([ -n "$ARG_OPENAI_API_KEY" ] && echo "Provided" || echo "Not provided")"
printf "Codex Model: %s\n" "${ARG_CODEX_MODEL:-"Default"}"
printf "Start Directory: %s\n" "$ARG_CODEX_START_DIRECTORY"
printf "Has Task Prompt: %s\n" "$([ -n "$ARG_CODEX_TASK_PROMPT" ] && echo "Yes" || echo "No")"
echo "======================================"
set +o nounset
CODEX_ARGS=()

if command_exists codex; then
  printf "Codex is installed\n"
else
  printf "Error: Codex is not installed. Please enable install_codex or install it manually\n"
  exit 1
fi

if [ -d "${ARG_CODEX_START_DIRECTORY}" ]; then
  printf "Directory '%s' exists. Changing to it.\\n" "${ARG_CODEX_START_DIRECTORY}"
  cd "${ARG_CODEX_START_DIRECTORY}" || {
    printf "Error: Could not change to directory '%s'.\\n" "${ARG_CODEX_START_DIRECTORY}"
    exit 1
  }
else
  printf "Directory '%s' does not exist. Creating and changing to it.\\n" "${ARG_CODEX_START_DIRECTORY}"
  mkdir -p "${ARG_CODEX_START_DIRECTORY}" || {
    printf "Error: Could not create directory '%s'.\\n" "${ARG_CODEX_START_DIRECTORY}"
    exit 1
  }
  cd "${ARG_CODEX_START_DIRECTORY}" || {
    printf "Error: Could not change to directory '%s'.\\n" "${ARG_CODEX_START_DIRECTORY}"
    exit 1
  }
fi

if [ -n "$ARG_CODEX_MODEL" ]; then
  CODEX_ARGS+=("--model" "$ARG_CODEX_MODEL")
fi

if [ -n "$ARG_CODEX_TASK_PROMPT" ]; then
  printf "Running the task prompt %s\n" "$ARG_CODEX_TASK_PROMPT"
  PROMPT="Complete the task at hand in one go. Every step of the way, report your progress using coder_report_task tool with proper summary and statuses. Your task at hand: $ARG_CODEX_TASK_PROMPT"
  CODEX_ARGS+=("$PROMPT")
else
  printf "No task prompt given.\n"
fi

# Terminal dimensions optimized for Coder Tasks UI sidebar:
# - Width 67: fits comfortably in sidebar
# - Height 1190: adjusted due to Codex terminal height bug
printf "Starting Codex with arguments: %s\n" "${CODEX_ARGS[*]}"
agentapi server --term-width 67 --term-height 1190 -- codex "${CODEX_ARGS[@]}"
