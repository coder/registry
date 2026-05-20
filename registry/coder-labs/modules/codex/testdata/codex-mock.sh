#!/bin/bash

if [[ "$1" == "--version" ]]; then
  echo "codex version v1.0.0"
  exit 0
fi

echo "codex invoked with: $*"
exit 0
