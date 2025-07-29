#!/bin/bash
set -o errexit
set -o pipefail

# this must be kept in sync with the main.tf file
module_path="$HOME/.gemini-module"
scripts_dir="$module_path/scripts"
log_file_path="$module_path/agentapi.log"

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

if [ -n "$CODER_MCP_GEMINI_TASK_PROMPT" ]; then
    GEMINI_TASK_PROMPT=$(echo -n "$CODER_MCP_GEMINI_TASK_PROMPT" | base64 -d)
elif [ -n "$GEMINI_TASK_PROMPT" ]; then
    GEMINI_TASK_PROMPT=$(echo -n "$GEMINI_TASK_PROMPT" | base64 -d)
fi

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

if [ -n "$1" ]; then
    cp "$module_path/prompt.txt" /tmp/gemini-prompt 2>/dev/null || echo "" > /tmp/gemini-prompt
else
    rm -f /tmp/gemini-prompt
fi

if [ -f "$log_file_path" ]; then
    mv "$log_file_path" "$log_file_path"".$(date +%s)"
fi

# Clean up stale session IDs to avoid continuation issues
# see the remove-last-session-id.js script for details about why we need it
# avoid exiting if the script fails
if [ -f "$scripts_dir/remove-last-session-id.js" ]; then
    node "$scripts_dir/remove-last-session-id.js" "$(pwd)" || true
fi

# we'll be manually handling errors from this point on
set +o errexit

function start_gemini_agentapi() {
    local continue_flag="$1"
    local prompt_subshell=""
    
    if [ -n "$GEMINI_TASK_PROMPT" ]; then
        printf "Running the task prompt %s\n" "$GEMINI_TASK_PROMPT"
        PROMPT="Every step of the way, report tasks to Coder with proper descriptions and statuses. Your task at hand: $GEMINI_TASK_PROMPT"
        GEMINI_ARGS=(--prompt-interactive "$PROMPT")
    elif [ -f "/tmp/gemini-prompt" ] && [ -s "/tmp/gemini-prompt" ]; then
        prompt_subshell='"$(cat /tmp/gemini-prompt)"'
        GEMINI_ARGS=()
    else
        printf "No task prompt given.\n"
        GEMINI_ARGS=()
    fi

    if [ -n "$GEMINI_API_KEY" ]; then
        printf "gemini_api_key provided !\n"
    else
        printf "gemini_api_key not provided\n"
    fi
    
    if [ -n "$prompt_subshell" ]; then
        agentapi server --term-width 67 --term-height 1190 -- \
            bash -c "gemini $continue_flag $prompt_subshell" \
            > "$log_file_path" 2>&1
    else
        agentapi server --term-width 67 --term-height 1190 -- \
            gemini $continue_flag "${GEMINI_ARGS[@]}" \
            > "$log_file_path" 2>&1
    fi
}

echo "Starting Gemini via AgentAPI..."

start_gemini_agentapi --continue
exit_code=$?

echo "First Gemini AgentAPI exit code: $exit_code"

if [ $exit_code -eq 0 ]; then
    exit 0
fi

if grep -q -i "no conversation\|no session\|cannot continue\|not found" "$log_file_path" 2>/dev/null; then
    echo "AgentAPI with --continue flag failed, starting gemini without it."
    start_gemini_agentapi
    exit_code=$?
fi

echo "Second Gemini AgentAPI exit code: $exit_code"

exit $exit_code