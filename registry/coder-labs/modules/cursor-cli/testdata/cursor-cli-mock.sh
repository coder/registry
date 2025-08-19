#!/bin/bash

if [[ "$1" == "--version" ]]; then
  echo "HELLO: $(bash -c env)"
  echo "cursor-agent version v2.5.0"
  exit 0
fi

set -e

while true; do
    echo "$(date) - cursor-agent-mock"
    sleep 15
done