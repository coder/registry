#!/bin/bash
set -o errexit
set -o pipefail

# this must be kept in sync with the main.tf file
module_path="$HOME/.claude-module"
scripts_dir="$module_path/scripts"
log_file_path="$module_path/agentapi.log"

# if the first argument is not empty, start claude with the prompt
if [ -n "$1" ]; then
  cp "$module_path/prompt.txt" /tmp/claude-code-prompt
else
  rm -f /tmp/claude-code-prompt
fi

# if the log file already exists, archive it
if [ -f "$log_file_path" ]; then
  mv "$log_file_path" "$log_file_path"".$(date +%s)"
fi

# see the remove-last-session-id.sh script for details
# about why we need it
# avoid exiting if the script fails
bash "$scripts_dir/remove-last-session-id.sh" "$(pwd)" 2> /dev/null || true

# we'll be manually handling errors from this point on
set +o errexit

function start_agentapi() {
  local continue_flag="$1"
  local prompt_subshell='"$(cat /tmp/claude-code-prompt)"'

  # use low width to fit in the tasks UI sidebar. height is adjusted so that width x height ~= 80x1000 characters
  # visible in the terminal screen by default.
  agentapi server --term-width 67 --term-height 1190 -- \
    bash -c "claude $continue_flag --dangerously-skip-permissions $prompt_subshell" \
    > "$log_file_path" 2>&1
}

echo "Starting AgentAPI..."

# attempt to start claude with the --continue flag
start_agentapi --continue
exit_code=$?

echo "First AgentAPI exit code: $exit_code"

if [ $exit_code -eq 0 ]; then
  exit 0
fi

# if there was no conversation to continue, claude exited with an error.
# start claude without the --continue flag.
if grep -q "No conversation found to continue" "$log_file_path"; then
  echo "AgentAPI with --continue flag failed, starting claude without it."
  start_agentapi
  exit_code=$?
fi

echo "Second AgentAPI exit code: $exit_code"

exit $exit_code
