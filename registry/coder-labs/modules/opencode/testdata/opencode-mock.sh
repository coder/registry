#!/usr/bin/env bash

# Minimal OpenCode 2 stand-in. Credentials live in a JSON array file so tests
# can assert on `auth import`/`auth logout` semantics.
store="${HOME}/.opencode-mock-credentials.json"
[[ -f "${store}" ]] || echo '[]' > "${store}"

args=()
for arg in "$@"; do
  [[ "${arg}" = "--standalone" ]] || args+=("${arg}")
done
set -- "${args[@]}"

case "$1 ${2:-}" in
  "--version "* | "-v "*)
    echo "opencode v2.0.0-mock"
    ;;
  "auth export")
    cat "${store}"
    ;;
  "auth import")
    incoming=$(cat)
    echo "auth import invoked" >> /tmp/opencode-mock-calls
    jq --argjson new "${incoming}" '. as $old | $old + [$new[] | select(.id as $id | ($old | map(.id) | index($id)) == null)]' "${store}" > "${store}.tmp"
    mv "${store}.tmp" "${store}"
    echo "Imported credentials"
    ;;
  "auth logout")
    echo "auth logout $3 $4" >> /tmp/opencode-mock-calls
    jq --arg id "$4" 'map(select(.id != $id))' "${store}" > "${store}.tmp"
    mv "${store}.tmp" "${store}"
    ;;
  *)
    echo "opencode invoked with: $*"
    ;;
esac
exit 0
