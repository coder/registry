#!/usr/bin/env bash

# Convert templated variables to shell variables
SESSION_NAME='${SESSION_NAME}'

# Function to check if tmux is installed
check_tmux() {
  if ! command -v tmux &> /dev/null; then
    echo "tmux is not installed. Please run the tmux setup script first."
    exit 1
  fi
}

# Function to handle a single session
handle_session() {
  local session_name="$1"

  # Check if the session exists
  if tmux has-session -t "$session_name" 2>/dev/null; then
    echo "Session '$session_name' exists, attaching to it..."
    tmux attach-session -t "$session_name"
  else
    echo "Session '$session_name' does not exist, creating it..."
    tmux new-session -d -s "$session_name"
    tmux attach-session -t "$session_name"
  fi
}

# Main function
main() {
  # Check if tmux is installed
  check_tmux
  handle_session "${SESSION_NAME}"
}

# Run the main function
main
