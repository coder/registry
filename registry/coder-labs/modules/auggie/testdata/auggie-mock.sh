#!/usr/bin/env bash

# Minimal Auggie CLI stand-in. `mcp add-json` keeps an existing name and exits
# 3 like the real CLI does without --replace.
settings="${HOME}/.augment/settings.json"

case "$1 ${2:-}" in
  "--version "*)
    echo "0.36.0 (commit mock)"
    ;;
  "mcp add-json")
    mkdir -p "$(dirname "${settings}")"
    [[ -f "${settings}" ]] || echo '{}' > "${settings}"
    if jq -e --arg name "$3" '(.mcpServers // {}) | has($name)' "${settings}" > /dev/null; then
      echo "Error: Server '$3' already exists; use --replace to overwrite" >&2
      exit 3
    fi
    jq --arg name "$3" --argjson server "$4" '.mcpServers[$name] = $server' "${settings}" > "${settings}.tmp"
    mv "${settings}.tmp" "${settings}"
    echo "Saved MCP server: {\"$3\":$4}"
    ;;
  *)
    echo "auggie invoked with: $*"
    ;;
esac
exit 0
