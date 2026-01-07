#!/bin/bash
set -o errexit
set -o pipefail
set -x

port=${1:-3284}

# This script waits for the agentapi server to start on port 3284.
# It considers the server started after 3 consecutive successful responses.

agentapi_started=false

echo "Waiting for agentapi server to start on port $port..."
for i in $(seq 1 30); do
    sleep 1
    if curl -f "http://localhost:$port/status"; then
      echo "agentapi response received"
      agentapi_started=true
      break
    else
      echo "agentapi server not responding ($i/30)"
      continue
    fi
done

if [ "$agentapi_started" != "true" ]; then
  echo "Error: agentapi server did not start on port $port after 15 seconds."
  exit 1
fi

echo "agentapi server started on port $port."
