#!/bin/bash
set -o errexit
set -o pipefail

port=${1:-3284}
max_attempts=150

# This script waits for the agentapi server to start on the given port.
# Each attempt sleeps 0.1s, so 150 attempts ≈ 15 seconds.
# It considers the server started after 3 consecutive successful responses.

agentapi_started=false

echo "Waiting for agentapi server to start on port $port..."
for i in $(seq 1 "$max_attempts"); do
  for j in $(seq 1 3); do
    sleep 0.1
    if curl -fs -o /dev/null "http://localhost:$port/status"; then
      echo "agentapi response received ($j/3)"
    else
      echo "agentapi server not responding ($i/$max_attempts)"
      continue 2
    fi
  done
  agentapi_started=true
  break
done

if [ "$agentapi_started" != "true" ]; then
  echo "Error: agentapi server did not start on port $port after $max_attempts attempts."
  exit 1
fi

echo "agentapi server started on port $port."
