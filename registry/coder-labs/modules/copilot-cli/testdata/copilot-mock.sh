#!/bin/bash
set -euo pipefail

if [[ "$1" == "--version" ]]; then
  echo "GitHub Copilot CLI v1.0.0"
  exit 0
fi

while true; do
  echo "$(date) - Copilot CLI mock running..."
  sleep 15
done
