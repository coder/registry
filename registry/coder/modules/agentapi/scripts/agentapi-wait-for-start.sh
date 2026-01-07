#!/bin/bash
#set -o errexit
set -o pipefail
set -x

port=${1:-3284}

# This script waits for the agentapi server to start on port 3284.
# It considers the server started after 3 consecutive successful responses.

agentapi_started=false

echo "Waiting for agentapi server to start on port $port..."
start=$(date +%s)
while true; do
    if curl -f "http://localhost:$port/status"; then
      agentapi_started=true
      elapsed=$(($(date +%s) - start))
      echo "$(date): agentapi server started after $elapsed seconds"
      break
    else
      echo "$(date): agentapi server not responding"
      agentapi_pid=$(pidof agentapi)
      if [ -z "$agentapi_pid" ]; then
        echo "$(date): agentapi process not found"
      else
        echo "$(date): agentapi pid: $agentapi_pid"
      fi
      boundary_pid=$(pidof boundary)
      if [ -z "$boundary_pid" ]; then
        echo "$(date): boundary process not found"
      else
        echo "$(date): boundary pid: $boundary_pid"
      fi
      sleep 1
      continue
    fi
done

if [ "$agentapi_started" != "true" ]; then
  echo "Error: agentapi server did not start on port $port after 15 seconds."
  exit 1
fi

echo "agentapi server started on port $port."
