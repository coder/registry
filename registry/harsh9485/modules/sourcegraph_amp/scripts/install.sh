#!/usr/bin/env bash
set -euo pipefail

# ANSI colors
BOLD='\033[1m'
RESET='\033[0m'

# Print arguments
echo "--------------------------------"
echo "Install flag: $ARG_INSTALL_SOURCEGRAPH_AMP"
echo "Workspace: $SOURCEGRAPH_AMP_START_DIRECTORY"
echo "--------------------------------"

# Check for npm/node and install via nvm if missing
function ensure_node() {
  if ! command -v npm &>/dev/null; then
    echo "npm not found. Installing Node.js via NVM..."
    export NVM_DIR="$HOME/.nvm"
    mkdir -p "$NVM_DIR"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
    # shellcheck source=/dev/null
    source "$NVM_DIR/nvm.sh"
    nvm install --lts
    nvm alias default node
  fi
}

function install_sourcegraph_amp() {
  if [[ "$ARG_INSTALL_SOURCEGRAPH_AMP" == "true" ]]; then
    ensure_node
    printf "%b Installing Sourcegraph AMP CLI...%b\n" "$BOLD" "$RESET"
    npm install -g @sourcegraph/amp
    export AMP_API_KEY="$SOURCEGRAPH_AMP_API_KEY"
    printf "%b Installation complete.%b\n" "$BOLD" "$RESET"
  fi
}

install_sourcegraph_amp