#!/bin/bash
set -euo pipefail

LOG_PREFIX="[1claw-mcp]"

log() {
  echo "$LOG_PREFIX $*"
}

API_TOKEN="${API_TOKEN}"
VAULT_ID="${VAULT_ID}"

# In bootstrap mode, API_TOKEN and VAULT_ID are empty at templatefile time.
# Wait for bootstrap.sh to produce the state file (scripts run concurrently).
BOOTSTRAP_MODE="${BOOTSTRAP_MODE}"
STATE_FILE="$HOME/.1claw/bootstrap.json"
if [ -z "$API_TOKEN" ] && [ "$BOOTSTRAP_MODE" = "true" ]; then
  WAIT_SECS=0
  while [ ! -f "$STATE_FILE" ] && [ "$WAIT_SECS" -lt 120 ]; do
    log "Waiting for bootstrap to complete ($WAIT_SECS/120s)..."
    sleep 3
    WAIT_SECS=$((WAIT_SECS + 3))
  done
fi

if [ -z "$API_TOKEN" ] && [ -f "$STATE_FILE" ]; then
  log "Loading credentials from bootstrap state"
  API_TOKEN=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['agent_api_key'])")
  VAULT_ID=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['vault_id'])")
fi

if [ -z "$API_TOKEN" ] || [ -z "$VAULT_ID" ]; then
  log "WARNING: No API token or vault ID available — skipping MCP config"
  log "Provide api_token + vault_id, or use human_api_key for bootstrap mode"
  exit 0
fi

# Build the MCP config JSON via python3 for safe handling of special characters.
MCP_CONFIG=$(
  python3 - "$API_TOKEN" "$VAULT_ID" << 'PYEOF'
import json, sys
config = {
    "mcpServers": {
        "1claw": {
            "url": "${MCP_HOST}",
            "headers": {
                "Authorization": "Bearer " + sys.argv[1],
                "X-Vault-ID": sys.argv[2]
            }
        }
    }
}
print(json.dumps(config, indent=2))
PYEOF
)

# Write MCP_CONFIG to a temp file so the merge script can read it safely.
MCP_CONFIG_TMP=$(mktemp)
trap 'rm -f "$MCP_CONFIG_TMP"' EXIT
echo "$MCP_CONFIG" > "$MCP_CONFIG_TMP"

write_config() {
  local target_path="$1"
  local label="$2"

  # Expand $HOME in the path
  target_path=$(eval echo "$target_path")

  local target_dir
  target_dir=$(dirname "$target_path")

  if [ ! -d "$target_dir" ]; then
    log "Creating directory $target_dir for $label config"
    mkdir -p "$target_dir"
  fi

  if [ -f "$target_path" ]; then
    log "Merging 1Claw MCP server into existing $label config at $target_path"
    if command -v python3 &> /dev/null; then
      python3 - "$target_path" "$MCP_CONFIG_TMP" << 'PYEOF'
import json, sys

target_path = sys.argv[1]
new_config_path = sys.argv[2]

existing = {}
try:
    with open(target_path) as f:
        existing = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    pass

with open(new_config_path) as f:
    new_server = json.load(f)

existing.setdefault("mcpServers", {}).update(new_server.get("mcpServers", {}))

with open(target_path, "w") as f:
    json.dump(existing, f, indent=2)
PYEOF
    else
      log "python3 not found — overwriting $target_path"
      cat "$MCP_CONFIG_TMP" > "$target_path"
    fi
  else
    log "Writing $label MCP config to $target_path"
    cat "$MCP_CONFIG_TMP" > "$target_path"
  fi

  chmod 600 "$target_path"
  log "$label MCP config ready at $target_path"
}

# Cursor IDE config
if [ "${INSTALL_CURSOR_CONFIG}" = "true" ]; then
  write_config "${CURSOR_CONFIG_PATH}" "Cursor"
fi

# Claude Code config
if [ "${INSTALL_CLAUDE_CONFIG}" = "true" ]; then
  write_config "${CLAUDE_CONFIG_PATH}" "Claude Code"
fi

log "1Claw MCP setup complete"
