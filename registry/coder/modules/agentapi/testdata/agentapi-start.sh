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

agentapi server --port "$port" --term-width 67 --term-height 1190 -- \
  bash -c aiagent \
  > "$log_file_path" 2>&1
