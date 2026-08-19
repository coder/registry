#!/usr/bin/env bash

set -euo pipefail

if [ "${1:-}" = "version" ] || [ "${1:-}" = "--version" ]; then
  printf '1.35.0\n'
  exit 0
fi

if [ "${1:-}" != "start" ]; then
  printf 'unexpected CloudCLI command: %s\n' "$*" >&2
  exit 2
fi

module_root="$(dirname "$(dirname "$DATABASE_PATH")")"
printf '%s\n' "$*" > "$module_root/run/mock-arguments"
printf 'HOST=%s\nSERVER_PORT=%s\nDATABASE_PATH=%s\nWORKSPACES_ROOT=%s\n' \
  "$HOST" \
  "$SERVER_PORT" \
  "$DATABASE_PATH" \
  "${WORKSPACES_ROOT:-}" \
  > "$module_root/run/mock-environment"

exec node << 'NODE'
const http = require("node:http");

const server = http.createServer((request, response) => {
  if (request.url === "/health") {
    response.writeHead(200, { "content-type": "application/json" });
    response.end(JSON.stringify({ status: "ok" }));
    return;
  }

  response.writeHead(404);
  response.end();
});

server.listen(Number(process.env.SERVER_PORT), process.env.HOST);
NODE
