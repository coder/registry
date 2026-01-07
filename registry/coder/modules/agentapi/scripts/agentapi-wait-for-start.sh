#!/bin/bash
set -o errexit
set -o pipefail

port=${1:-3284}
start_timeout=${2:-30}
listen_timeout=${3:-30}

# This script waits for the agentapi server to start on port 3284.
# It considers the server started after 3 consecutive successful responses.

agentapi_started=false

echo "Waiting for agentapi process to start..."
start=$(date +%s)
while true; do
    now=$(date +%s)
    elapsed=$(( now - start ))
    if [[ "${elapsed}" -gt "${start_timeout}" ]]; then
        echo "agentapi process not found after ${start_timeout} seconds"
        exit 1
    fi
    set +e
    agentapi_pid=$(pidof agentapi)
    set -e
    if [[ -z "${agentapi_pid}" ]]; then
        echo "agentapi process not found (${elapsed}/${start_timeout})"
        sleep 1
        continue
    fi
    echo "agentapi process started with pid ${agentapi_pid} after ${elapsed} seconds"
    break
done

echo "Waiting for agentapi to start listening on port ${port}..."
start=$(date +%s)
while true; do
  now=$(date +%s)
  elapsed=$(( now - start ))
  if [[ "${elapsed}" -gt "${listen_timeout}" ]]; then
    echo "agentapi server not listening on port ${port} after ${listen_timeout} seconds"
    exit 1
  fi
  for j in $(seq 1 3); do
    if curl -fs -o /dev/null "http://localhost:${port}/status"; then
      echo "agentapi response received (${j}/3)"
      sleep 0.1
      continue
    else
      echo "agentapi server not responding (${elapsed}/${listen_timeout})"
      sleep 1
      continue 2
    fi
  done
  echo "agentapi server started responding after ${elapsed} seconds"
  break
done

echo "agentapi server started on port ${port}."
