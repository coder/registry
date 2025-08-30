#!/bin/bash

if [[ "$1" == "--version" ]]; then
  echo "claude version v1.0.0"
  exit 0
fi

set -e

while true; do
  echo "$(date) - claude-mock"
  sleep 15
done
