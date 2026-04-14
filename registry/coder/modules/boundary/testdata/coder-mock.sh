#!/bin/bash

# Mock coder command for testing boundary module
# Handles: coder boundary [--help | -- <command>]

if [[ "$1" == "boundary" ]]; then
  shift

  # Handle --help flag
  if [[ "$1" == "--help" ]]; then
    cat << 'EOF'
boundary - Run commands in network isolation

Usage:
  coder boundary [flags] -- <command> [args...]

Examples:
  coder boundary -- curl https://example.com
  coder boundary -- npm install

Flags:
  -h, --help   help for boundary
EOF
    exit 0
  fi

  # Handle command execution after --
  if [[ "$1" == "--" ]]; then
    shift
    # Execute the command that follows
    exec "$@"
  fi

  # If no -- separator, just print help
  echo "Error: Expected '--' separator before command"
  exit 1
fi

echo "Mock coder: Unknown command: $*"
exit 1
