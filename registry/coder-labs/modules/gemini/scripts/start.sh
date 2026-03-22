#!/bin/bash
set -o errexit
set -o pipefail

source "$HOME"/.bashrc

set -o nounset

GEMINI_API_KEY=$(echo -n "$GEMINI_API_KEY" | base64 -d)
GOOGLE_API_KEY=$(echo -n "$GOOGLE_API_KEY" | base64 -d)
GOOGLE_GENAI_USE_VERTEXAI=$(echo -n "$GOOGLE_GENAI_USE_VERTEXAI" | base64 -d)
GEMINI_YOLO_MODE=$(echo -n "$GEMINI_YOLO_MODE" | base64 -d)
GEMINI_MODEL=$(echo -n "$GEMINI_MODEL" | base64 -d)
GEMINI_START_DIRECTORY=$(echo -n "$GEMINI_START_DIRECTORY" | base64 -d)
GEMINI_TASK_PROMPT=$(echo -n "$GEMINI_TASK_PROMPT" | base64 -d)

set +o nounset

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

if [ -f "$HOME/.nvm/nvm.sh" ]; then
  source "$HOME"/.nvm/nvm.sh
else
  export PATH="$HOME/.npm-global/bin:$PATH"
fi

printf "Version: %s\n" "$(gemini --version)"

MODULE_DIR="$HOME/.gemini-module"
mkdir -p "$MODULE_DIR"

if command_exists gemini; then
  printf "Gemini is installed\n"
else
  printf "Error: Gemini is not installed. Please enable install_gemini or install it manually :)\n"
  exit 1
fi

if [ -d "${GEMINI_START_DIRECTORY}" ]; then
  printf "Directory '%s' exists. Changing to it.\\n" "${GEMINI_START_DIRECTORY}"
  cd "${GEMINI_START_DIRECTORY}" || {
    printf "Error: Could not change to directory '%s'.\\n" "${GEMINI_START_DIRECTORY}"
    exit 1
  }
else
  printf "Directory '%s' does not exist. Creating and changing to it.\\n" "${GEMINI_START_DIRECTORY}"
  mkdir -p "${GEMINI_START_DIRECTORY}" || {
    printf "Error: Could not create directory '%s'.\\n" "${GEMINI_START_DIRECTORY}"
    exit 1
  }
  cd "${GEMINI_START_DIRECTORY}" || {
    printf "Error: Could not change to directory '%s'.\\n" "${GEMINI_START_DIRECTORY}"
    exit 1
  }
fi

if [ -n "$GEMINI_API_KEY" ] || [ -n "$GOOGLE_API_KEY" ]; then
  if [ -n "$GOOGLE_GENAI_USE_VERTEXAI" ] && [ "$GOOGLE_GENAI_USE_VERTEXAI" = "true" ]; then
    printf "Using Vertex AI with API key\n"
  else
    printf "Using direct Gemini API with API key\n"
  fi
else
  printf "No API key provided (neither GEMINI_API_KEY nor GOOGLE_API_KEY)\n"
  exit 1
fi

if [ -n "$GEMINI_YOLO_MODE" ] && [ "$GEMINI_YOLO_MODE" = "true" ]; then
  printf "YOLO mode enabled - will auto-approve all tool calls\n"
  GEMINI_ARGS=(--yolo)
fi

SESSION_FOLDER_NAME=$(basename "${GEMINI_START_DIRECTORY}")
if [ ! -d "$GEMINI_START_DIRECTORY/.gemini/tmp/$SESSION_FOLDER_NAME/chats/" ]; then
  printf "No existing Gemini chats found. Starting Gemini CLI in interactive mode.\n"
  if [ -n "$GEMINI_TASK_PROMPT" ]; then
    printf "Running automated task: %s\n" "$GEMINI_TASK_PROMPT"
    PROMPT="Every step of the way, report tasks to Coder with proper descriptions and statuses. Your task at hand: $GEMINI_TASK_PROMPT"
    PROMPT_FILE="$MODULE_DIR/prompt.txt"
    echo -n "$PROMPT" > "$PROMPT_FILE"
    GEMINI_ARGS+=(--prompt-interactive "$PROMPT")
  else
    printf "Starting Gemini CLI in interactive mode.\n"
    GEMINI_ARGS+=()
  fi
  agentapi server --type gemini --term-width 67 --term-height 1190 -- \
    bash -c "$(printf '%q ' gemini "${GEMINI_ARGS[@]}")"
else
  printf "Existing Gemini chats detected. Starting Gemini CLI in interactive mode with existing chats.\n"
  GEMINI_ARGS+=(--resume)
  agentapi server --type gemini --term-width 67 --term-height 1190 -- \
    bash -c "$(printf '%q ' gemini "${GEMINI_ARGS[@]}")"
fi
