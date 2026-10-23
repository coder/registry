#!/usr/bin/env bash

if [[ "$1" == "--version" ]]; then
  echo "aider 0.86.0-mock"
  exit 0
fi

echo "aider invoked with: $*"
