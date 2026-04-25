#!/bin/bash

if [[ "$1" == "--version" ]]; then
  echo "claude version v1.0.0"
  exit 0
fi

# Mirror invocation for test assertions and exit cleanly.
echo "claude invoked with: $*"
exit 0
