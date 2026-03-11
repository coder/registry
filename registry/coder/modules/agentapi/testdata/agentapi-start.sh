#!/bin/bash
set -o errexit
set -o pipefail

use_prompt=${1:-false}
port=${2:-3284}

module_path="$HOME/.agentapi-module"
log_file_path="$module_path/agentapi.log"

echo "using prompt: $use_prompt" >> /home/coder/test-agentapi-start.log
echo "using port: $port" >> /home/coder/test-agentapi-start.log

AGENTAPI_CHAT_BASE_PATH="${AGENTAPI_CHAT_BASE_PATH:-}"
if [ -n "$AGENTAPI_CHAT_BASE_PATH" ]; then
  echo "Using AGENTAPI_CHAT_BASE_PATH: $AGENTAPI_CHAT_BASE_PATH" >> /home/coder/test-agentapi-start.log
  export AGENTAPI_CHAT_BASE_PATH
fi

# Use boundary wrapper if configured by agentapi module.
# AGENTAPI_BOUNDARY_PREFIX is set by the agentapi module's main.sh
# and points to a wrapper script that runs the command through coder boundary.
if [ -n "${AGENTAPI_BOUNDARY_PREFIX:-}" ]; then
  echo "Starting with boundary: ${AGENTAPI_BOUNDARY_PREFIX}" >> /home/coder/test-agentapi-start.log
  agentapi server --port "$port" --term-width 67 --term-height 1190 -- \
    "${AGENTAPI_BOUNDARY_PREFIX}" bash -c aiagent \
    > "$log_file_path" 2>&1
else
  agentapi server --port "$port" --term-width 67 --term-height 1190 -- \
    bash -c aiagent \
    > "$log_file_path" 2>&1
fi
