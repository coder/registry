#!/bin/bash

set -euo pipefail

BOLD='\033[0;1m'

# Parse arguments
ARG_ENABLE_SUBAGENTS="${ARG_ENABLE_SUBAGENTS:-false}"
ARG_SUBAGENTS_VERSION="${ARG_SUBAGENTS_VERSION:-latest}"
ARG_CUSTOM_SUBAGENTS_PATH="${ARG_CUSTOM_SUBAGENTS_PATH:-}"
ARG_ENABLED_SUBAGENTS="${ARG_ENABLED_SUBAGENTS:-}"
ARG_DEFAULT_SUBAGENT_MODEL="${ARG_DEFAULT_SUBAGENT_MODEL:-claude-sonnet-4-20250514}"

# Create Claude config directory
CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR"

# Install subagents if enabled
if [ "$ARG_ENABLE_SUBAGENTS" = "true" ]; then
  printf "%s Installing Claude Code subagents...\n" "${BOLD}"

  if [ -n "$ARG_CUSTOM_SUBAGENTS_PATH" ]; then
    # Use custom subagents path
    printf "Using custom subagents from: %s\n" "$ARG_CUSTOM_SUBAGENTS_PATH"
    mkdir -p "$CLAUDE_DIR/agents"
    cp -r "$ARG_CUSTOM_SUBAGENTS_PATH"/* "$CLAUDE_DIR/agents/"
  else
    # Clone the default agents repository
    AGENTS_DIR="$CLAUDE_DIR/agents"
    if [ ! -d "$AGENTS_DIR" ]; then
      git clone https://github.com/wshobson/agents.git "$AGENTS_DIR"
    fi
    cd "$AGENTS_DIR"

    if [ "$ARG_SUBAGENTS_VERSION" = "latest" ]; then
      git pull origin main
    else
      git checkout "$ARG_SUBAGENTS_VERSION"
    fi
  fi

  # Configure enabled subagents
  if [ -n "$ARG_ENABLED_SUBAGENTS" ]; then
    printf "Configuring enabled subagents: %s\n" "$ARG_ENABLED_SUBAGENTS"
    mkdir -p "$CLAUDE_DIR/config"
    echo "{\"enabledAgents\": $ARG_ENABLED_SUBAGENTS, \"defaultModel\": \"$ARG_DEFAULT_SUBAGENT_MODEL\"}" > "$CLAUDE_DIR/config/agents.json"
  fi

  printf "%s Claude Code subagents installed successfully\n" "${BOLD}"
fi

# Install Claude Code
printf "%s Installing Claude Code...\n" "${BOLD}"
if command -v npm &> /dev/null; then
  npm install -g @anthropic/claude-code
else
  echo "npm not found. Please install Node.js and npm first."
  exit 1
fi

printf "%s Claude Code installation complete\n" "${BOLD}"
