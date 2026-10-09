#!/usr/bin/env bash

if [[ "$1" == "--version" || "$1" == "-v" ]]; then
  echo "0.0.0-mock"
  exit 0
fi

echo "opencode invoked with: $*"
exit 0
