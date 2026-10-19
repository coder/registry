#!/usr/bin/env bash
# Stands in for selkies: answers `selkies session --help` as Selkies 2.1.0
# does, and for `selkies session` records how it was started and answers
# /api/health on the port it was given, as Selkies does
[[ "${1:-}" = session ]] || exit 2
shift
if [[ "${1:-}" = --help ]]; then
  echo "usage: selkies session [-h] [--session SESSION]"
  exit 0
fi
printf '%s\n' "$@" > /tmp/selkies.args
printf 'SELKIES_WAYLAND=%s\n' "${SELKIES_WAYLAND:-}" > /tmp/selkies.env
port=8080
for arg in "$@"; do
  case "${arg}" in
    --port=*) port=${arg#--port=} ;;
    *) ;;
  esac
done
exec node -e '
  require("node:http")
    .createServer((req, res) => {
      res.writeHead(req.url === "/api/health" ? 200 : 404);
      res.end();
    })
    .listen(Number(process.argv[1]), "127.0.0.1");
' "${port}"
