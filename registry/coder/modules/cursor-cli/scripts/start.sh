#!/bin/bash

# Function to check if a command exists
command_exists() {
  command -v "$1" > /dev/null 2>&1
}

# Set working directory
if [ -n "${ARG_FOLDER:-}" ] && [ -d "${ARG_FOLDER}" ]; then
  cd "${ARG_FOLDER}" || {
    echo "Warning: Could not change to directory ${ARG_FOLDER}, using current directory"
  }
fi

# Find cursor-agent command
if command_exists cursor-agent; then
  CURSOR_CMD=cursor-agent
elif [ -f "$HOME/.cursor/bin/cursor-agent" ]; then
  CURSOR_CMD="$HOME/.cursor/bin/cursor-agent"
else
  echo "Error: Cursor CLI is not installed. Please enable install_cursor_cli or install it manually."
  echo "You can install it manually with: curl https://cursor.com/install -fsS | bash"
  exit 1
fi

echo "Starting Cursor CLI in $(pwd)"
echo "Interactive mode with text output enabled"
echo "Available commands:"
echo "  - Start interactive session: cursor-agent"
echo "  - Non-interactive mode: cursor-agent -p 'your prompt here'"
echo "  - With specific model: cursor-agent -p 'prompt' --model 'gpt-5'"
echo "  - Text output format: cursor-agent -p 'prompt' --output-format text"
echo "  - List sessions: cursor-agent ls"
echo "  - Resume session: cursor-agent resume"
echo ""

# Configure for interactive mode with text output
# If no arguments provided, start in interactive mode
if [ $# -eq 0 ]; then
  echo "Starting interactive session..."
  exec "$CURSOR_CMD"
else
  # Pass through all arguments for custom usage
  exec "$CURSOR_CMD" "$@"
fi
