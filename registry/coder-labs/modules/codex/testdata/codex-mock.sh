#!/bin/bash

if [[ "$1" == "--version" ]]; then
  echo "HELLO: $(bash -c env)"
  echo "codex version v1.0.0"
  exit 0
fi

set -e

while true; do
  echo "$(date) - codex-mock"
  sleep 15
done
