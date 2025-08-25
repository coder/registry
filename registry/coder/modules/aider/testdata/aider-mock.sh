#!/bin/bash

if [[ "$1" == "--version" ]]; then
  echo "HELLO: $(bash -c env)"
  echo "aider version v0.86.0"
  exit 0
fi

set -e

while true; do
    echo "$(date) - aider-agent-mock"
    sleep 15
done