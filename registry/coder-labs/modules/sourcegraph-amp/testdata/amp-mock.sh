#!/usr/bin/env bash

if [[ "$1" == "--version" ]]; then
  echo "0.0.1700000000-gmock00 (released 2026-01-01T00:00:00.000Z, 1d ago)"
  exit 0
fi

echo "amp invoked with: $*"
exit 0
