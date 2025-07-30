#!/bin/bash

if [[ "$1" == "--version" ]]; then
  echo "HELLO: $(bash -c env)"
  echo "gemini version v2.5.0"
  exit 0
fi

set -e

while true; do
    echo "$(date) - gemini-mock"
    sleep 15
done