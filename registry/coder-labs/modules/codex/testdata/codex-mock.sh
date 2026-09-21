#!/bin/bash

if [[ "$1" == "--version" ]]; then
  echo "codex version v1.0.0"
  exit 0
fi

if [[ "$1" == "login" && "$2" == "--with-api-key" ]]; then
  umask 077
  cat > /tmp/codex-login-stdin
  echo "codex invoked with: login --with-api-key"
  exit "${CODEX_LOGIN_EXIT_CODE:-0}"
fi

echo "codex invoked with: $*"
exit 0
