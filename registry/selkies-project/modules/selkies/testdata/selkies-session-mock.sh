#!/usr/bin/env bash
# Stands in for selkies-session: records how it was started, and answers
# /api/health on the port it was given, as Selkies does
printf '%s\n' "$@" > /tmp/selkies-session.args
printf 'SELKIES_WAYLAND=%s\n' "${SELKIES_WAYLAND:-}" > /tmp/selkies-session.env
port=8080
for arg in "$@"; do
  case "$arg" in --port=*) port=${arg#--port=} ;; esac
done
exec node -e '
  require("node:http")
    .createServer((req, res) => {
      res.writeHead(req.url === "/api/health" ? 200 : 404);
      res.end();
    })
    .listen(Number(process.argv[1]), "127.0.0.1");
' "$port"
