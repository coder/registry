#!/bin/bash

# Mock OpenCode CLI for testing purposes
# This script simulates the OpenCode command-line interface

echo "OpenCode Mock CLI - Test Version"
echo "Args received: $*"

# Simulate opencode behavior based on arguments
case "$1" in
  --version|-v)
    echo "opencode mock version 0.1.0-test"
    ;;
  --help|-h)
    echo "OpenCode Mock Help"
    echo "Usage: opencode [options] [command]"
    echo "This is a mock version for testing"
    ;;
  *)
    echo "Running OpenCode mock with arguments: $*"
    echo "Mock execution completed successfully"
    ;;
esac

exit 0