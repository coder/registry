#!/usr/bin/env bash

# Convert templated variables to shell variables
SESSIONS='${SESSIONS}'

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

  # If no sessions are specified, create or attach to a default session
  if [ "$SESSIONS" = "[]" ] || [ -z "$SESSIONS" ]; then
    echo "No sessions specified, using default session..."
    handle_session "default"
    exit 0
  fi

  # Parse the JSON array by removing brackets and quotes, then split by commas
  # Remove the opening and closing brackets
  sessions_str=$${SESSIONS#[}
  sessions_str=$${sessions_str%]}

  # Remove quotes and split by commas
  sessions_str=$(echo "$sessions_str" | sed s/\"//g)
  IFS=',' read -ra SESSION_ARRAY <<< "$sessions_str"

  # Handle each session
  for session in "$${SESSION_ARRAY[@]}"; do
    # Trim whitespace
    session=$(echo "$session" | sed s/^[[:space:]]*//\;s/[[:space:]]*$//)
    handle_session "$session"
  done
}

# Run the main function
main
