#!/bin/bash

# Mock behavior of the AMP CLI
if [[ "$1" == "--version" ]]; then
  echo "AMP CLI mock version v1.0.0"
  exit 0
fi

# Simulate AMP running in a loop for AgentAPI to connect
set -e
while true; do
  echo "$(date) - AMP mock is running..."
  sleep 15
done
