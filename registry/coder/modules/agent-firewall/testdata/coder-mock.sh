#!/bin/bash

# Mock coder command for testing agent-firewall module
# Handles: coder agent-firewall [--help | <command>]
# Handles: coder boundary [--help | <command>]
# Handles: coder exp sync [want|start|complete] (no-op for testing)

# Handle exp sync commands (no-op for testing)
if [[ "$1" == "exp" ]] && [[ "$2" == "sync" ]]; then
  exit 0
fi

if [[ "$1" == "agent-firewall" ]] || [[ "$1" == "boundary" ]]; then
  shift

  # Handle --help flag
  if [[ "$1" == "--help" ]]; then
    cat << 'EOF'
agent-firewall - Run commands in network isolation

Usage:
  coder agent-firewall [flags] -- <command> [args...]

Examples:
  coder agent-firewall -- curl https://example.com
  coder agent-firewall -- npm install

Flags:
  -h, --help   help for agent-firewall
EOF
    exit 0
  fi

  # Execute the remaining arguments as a command
  exec "$@"
fi

echo "Mock coder: Unknown command: $*"
exit 1
