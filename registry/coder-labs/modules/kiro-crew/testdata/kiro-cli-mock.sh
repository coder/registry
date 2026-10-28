#!/usr/bin/env bash

if [[ "$1" == "--version" ]]; then
  echo "kiro-cli 0.0.0-test"
  exit 0
fi

echo "kiro-cli invoked with: $*"
exit 0
