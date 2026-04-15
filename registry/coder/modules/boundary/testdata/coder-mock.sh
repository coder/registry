#!/bin/bash

# Mock coder command for testing boundary module
# Handles: coder boundary [--help | <command>]
# Handles: coder exp sync [want|start|complete] (no-op for testing)

# Handle exp sync commands (no-op for testing)
if [[ "$1" == "exp" ]] && [[ "$2" == "sync" ]]; then
  exit 0
fi

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

  # Execute the remaining arguments as a command
  exec "$@"
fi

echo "Mock coder: Unknown command: $*"
exit 1
