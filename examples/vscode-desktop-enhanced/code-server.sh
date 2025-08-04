#!/usr/bin/env bash

set -euo pipefail

# Install and start code-server
curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server

/tmp/code-server/bin/code-server \
  --auth none \
  --port 13337 \
  --bind-addr 0.0.0.0:13337 \
  --app-name "VS Code Web" \
  --welcome-text "Welcome to your Coder workspace!" \
  "${folder}"
