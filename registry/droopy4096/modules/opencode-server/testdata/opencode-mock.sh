#!/usr/bin/env bash
# Minimal stand-in for the OpenCode 1.x CLI used by main.test.ts.
set -euo pipefail

case "${1:-}" in
  --version)
    echo "${MOCK_OPENCODE_VERSION:-1.19.5}"
    ;;
  serve)
    shift
    host="127.0.0.1"
    port="4096"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --hostname) host="$2" && shift 2 ;;
        --port) port="$2" && shift 2 ;;
        *) shift ;;
      esac
    done
    echo "serve ${host}:${port}" >> /tmp/opencode-mock-calls
    exec node -e '
      const http = require("http");
      const expected = "Basic " + Buffer.from("opencode:" + process.env.OPENCODE_SERVER_PASSWORD).toString("base64");
      http.createServer((req, res) => {
        res.statusCode = req.headers.authorization === expected ? 200 : 401;
        res.end(req.url === "/global/health" ? "{\"healthy\":true}" : "");
      }).listen(Number(process.argv[2]), process.argv[1]);
    ' "${host}" "${port}"
    ;;
  *)
    echo "opencode-mock: unsupported args: $*" >&2
    exit 1
    ;;
esac
