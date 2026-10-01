#!/bin/bash

if [[ "$1" == "--version" ]]; then
  echo "pi version v1.0.0"
  exit 0
fi

echo "pi invoked with: $*"
exit 0
