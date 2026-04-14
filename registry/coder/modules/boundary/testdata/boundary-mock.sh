#!/bin/bash

# Mock boundary binary for testing
# Handles: boundary [--help | -- <command>]

if [[ "$1" == "--help" ]]; then
  cat << 'EOF'
boundary - Network isolation tool

Usage:
  boundary [flags] -- <command> [args...]

Examples:
  boundary -- curl https://example.com
  boundary -- npm install

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
