#!/bin/bash

if [[ "$1" == "--version" ]]; then
  echo "gemini version v1.0.0"
  exit 0
fi

echo "gemini invoked with: $*"
exit 0
