#!/usr/bin/env bash
set -euo pipefail

# Load user environment
# shellcheck source=/dev/null
source "$HOME/.bashrc"
# shellcheck source=/dev/null
source "$HOME/.nvm/nvm.sh"

function ensure_command() {
  command -v "$1" &>/dev/null || { echo "Error: '$1' not found." >&2; exit 1; }
}

ensure_command amp
echo "AMP version: $(amp --version)"


dir="$SOURCEGRAPH_AMP_START_DIRECTORY"
if [[ -d "$dir" ]]; then
  echo "Using existing directory: $dir"
else
  echo "Creating directory: $dir"
  mkdir -p "$dir"
fi
cd "$dir"

# Launch AgentAPI server with AMP
agentapi server --term-width=67 --term-height=1190 -- amp