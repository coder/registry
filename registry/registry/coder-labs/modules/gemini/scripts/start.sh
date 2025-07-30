#!/bin/bash

# Load shell environment
source "$HOME"/.bashrc

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

if [ -f "$HOME/.nvm/nvm.sh" ]; then
  source "$HOME"/.nvm/nvm.sh
else
  export PATH="$HOME/.npm-global/bin:$PATH"
fi

printf "Version: %s\n" "$(gemini --version)"

GEMINI_TASK_PROMPT=$(echo -n "$GEMINI_TASK_PROMPT" | base64 -d)

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

if [ -n "$GEMINI_TASK_PROMPT" ]; then
    printf "Running the task prompt %s\n" "$GEMINI_TASK_PROMPT"
    PROMPT="Every step of the way, report tasks to Coder with proper descriptions and statuses. Your task at hand: $GEMINI_TASK_PROMPT"
    GEMINI_ARGS=(--prompt-interactive "$PROMPT")
else
    printf "No task prompt given.\n"
    GEMINI_ARGS=()
fi

if [ -n "$GEMINI_API_KEY" ]; then
    printf "gemini_api_key provided !\n"
else
    printf "gemini_api_key not provided\n"
fi

# use low width to fit in the tasks UI sidebar. height is adjusted so that width x height ~= 80x1000 characters
# are visible in the terminal screen by default.
agentapi server --term-width 67 --term-height 1190 -- gemini "${GEMINI_ARGS[@]}"