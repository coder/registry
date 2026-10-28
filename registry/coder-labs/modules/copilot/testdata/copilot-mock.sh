#!/bin/bash
set -euo pipefail

# Minimal mock of the GitHub Copilot CLI used by the module tests.
case "${1:-}" in
  --version | -v)
    echo "GitHub Copilot CLI v1.0.0"
    exit 0
    ;;
  config)
    # e.g. `copilot config model <name>` — accept and succeed.
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
