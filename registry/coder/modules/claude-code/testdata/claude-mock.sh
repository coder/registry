#!/bin/bash

# Mock of the claude CLI used in bun tests. Needs to cover:
#   claude --version
#   claude mcp add-json --scope user <name> <json>
# Other invocations are ignored (no-op, exit 0).

if [[ "$1" == "--version" ]]; then
  echo "claude version v1.0.0"
  exit 0
fi

if [[ "$1" == "mcp" && "$2" == "add-json" ]]; then
  # Expected argv: mcp add-json --scope user <name> <json>
  # Echo the server name so tests can grep for it in install.log.
  name=""
  for ((i = 3; i <= $#; i++)); do
    arg="${!i}"
    if [[ "$arg" == --* ]]; then
      continue
    fi
    if [[ "$arg" == "user" || "$arg" == "project" || "$arg" == "local" ]]; then
      continue
    fi
    name="$arg"
    break
  done
  if [[ -n "$name" ]]; then
    echo "mock: added MCP server '$name' at user scope"
  fi
  exit 0
fi

# Fallback: stay alive so any orchestration that spawns claude doesn't exit
# the test container prematurely. Tests that need a quick claude return use
# --version above.
exit 0
