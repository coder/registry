#!/usr/bin/env bash

# Stand-in for the kirocrew CLI. Records every invocation and, for
# `kirocrew gateway`, records the environment it was launched with and starts
# a fake gateway that serves /health and /api/token/local.

echo "$*" >> /tmp/kirocrew-calls

case "$1" in
  --version)
    echo "kirocrew 0.0.0-test"
    ;;
  gateway)
    {
      echo "KIROCREW_PORT=$KIROCREW_PORT"
      echo "KIROCREW_CORS_ORIGINS=${KIROCREW_CORS_ORIGINS:-}"
      echo "KIRO_AWS_BUILDER_ID_TOKEN=${KIRO_AWS_BUILDER_ID_TOKEN:-}"
    } > /tmp/kirocrew-gateway-env
    if [ "${KIROCREW_MOCK_GATEWAY:-serve}" = "hang" ]; then
      exec sleep infinity
    fi
    mkdir -p "$HOME/.kiro/crew"
    echo "test-secret" > "$HOME/.kiro/crew/.local_secret"
    exec python3 /tmp/fake-gateway.py
    ;;
esac
exit 0
