#!/bin/bash

if [[ "$1" == "--version" ]]; then
  echo "HELLO: $(bash -c env)"
  echo "auggie version v1.0.0"
  exit 0
fi

set -e

while true; do
  echo "$(date) - auggie-mock"
  sleep 15
done
