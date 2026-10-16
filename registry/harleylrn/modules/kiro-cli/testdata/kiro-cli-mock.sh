#!/usr/bin/env bash

if [[ "$1" == "--version" ]]; then
  echo "kiro-cli 2.26.0"
  exit 0
fi

echo "kiro-cli invoked with: $*"
exit 0
