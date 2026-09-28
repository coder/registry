#!/usr/bin/env bash

if [[ "$1" == "--version" ]]; then
  echo "2026.01.01-mock"
  exit 0
fi

echo "cursor-agent invoked with: $*"
exit 0
