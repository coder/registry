#!/bin/bash

# Handle --version flag
if [[ "$1" == "--version" ]]; then
  echo "HELLO: $(bash -c env)"
  echo "codex version v1.0.0"
  exit 0
fi

set -e

SESSION_ID=""
IS_RESUME=false

while [[ $# -gt 0 ]]; do
  case $1 in
    resume)
      IS_RESUME=true
      SESSION_ID="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [ "$IS_RESUME" = false ]; then
  SESSION_ID="019a1234-5678-9abc-def0-123456789012"
  echo "Created new session: $SESSION_ID"
else
  echo "Resuming session: $SESSION_ID"
fi

while true; do
  echo "$(date) - codex-mock (session: $SESSION_ID)"
  sleep 15
done
