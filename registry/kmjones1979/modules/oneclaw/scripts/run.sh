#!/bin/bash
set -euo pipefail

LOG_PREFIX="[1claw]"
log() { echo "$LOG_PREFIX $*"; }
die() {
  log "ERROR: $*" >&2
  exit 1
}

BOOTSTRAP_MODE="${BOOTSTRAP_MODE}"
API_URL="${BASE_URL}"
VAULT_ID_INPUT="${VAULT_ID_INPUT}"
VAULT_NAME_IN="${VAULT_NAME}"
AGENT_NAME_IN="${AGENT_NAME}"
POLICY_PATH_IN="${POLICY_PATH}"
STATE_DIR=$(eval echo "${STATE_DIR}")
STATE_FILE="$STATE_DIR/bootstrap.json"

# Sensitive values come from env vars injected by coder_env (sensitive = true),
# NOT from templatefile() substitutions, so they do not appear in the Coder
# agent's rendered-script log (/tmp/coder-agent.log).
HUMAN_KEY="$${_ONECLAW_HUMAN_API_KEY:-}"
API_TOKEN="$${ONECLAW_AGENT_API_KEY:-}"
VAULT_ID="$${ONECLAW_VAULT_ID:-}"

json_get() {
  python3 -c "import json,sys; print(json.load(sys.stdin)$1)"
}

api_call() {
  local method="$1" path="$2" token="$3" body="$${4:-}"
  local response http_code body_out
  # Pass bearer token via stdin config to keep it out of process argv.
  # Body (if any) is piped on stdin as --data-binary.
  local curl_cfg
  curl_cfg=$(mktemp)
  printf -- 'header = "Authorization: Bearer %s"\n' "$token" > "$curl_cfg"
  if [ -n "$body" ]; then
    response=$(printf '%s' "$body" | curl -s -w "\n%%{http_code}" \
      -K "$curl_cfg" \
      -H "Content-Type: application/json" \
      --data-binary @- \
      -X "$method" "$API_URL$path" 2>&1)
  else
    response=$(curl -s -w "\n%%{http_code}" \
      -K "$curl_cfg" \
      -H "Content-Type: application/json" \
      -X "$method" "$API_URL$path" 2>&1)
  fi
  local rc=$?
  rm -f "$curl_cfg"
  if [ $rc -ne 0 ]; then
    log "API call failed: $method $path"
    return 1
  fi
  http_code=$(echo "$response" | tail -1)
  body_out=$(echo "$response" | sed '$d')
  if [ "$${http_code:0:1}" != "2" ]; then
    log "API error: $method $path returned HTTP $http_code"
    log "Response: $body_out"
    return 1
  fi
  echo "$body_out"
}

bootstrap() {
  if [ -f "$STATE_FILE" ]; then
    log "Bootstrap state found at $STATE_FILE — skipping provisioning"
    return 0
  fi

  [ -n "$HUMAN_KEY" ] || die "human_api_key is required for bootstrap mode"

  log "Authenticating with 1Claw API..."
  local auth_response auth_http auth_body jwt
  # Pipe the body via stdin so the 1ck_ key never appears in process argv (ps/proc/cmdline).
  auth_response=$(printf '{"api_key": "%s"}' "$HUMAN_KEY" | curl -s -w "\n%%{http_code}" \
    -H "Content-Type: application/json" \
    --data-binary @- \
    "$API_URL/v1/auth/api-key-token" 2>&1) || die "Failed to authenticate with human API key"

  # Key is no longer needed; scrub from process memory before any other work.
  HUMAN_KEY=""
  unset HUMAN_KEY

  auth_http=$(echo "$auth_response" | tail -1)
  auth_body=$(echo "$auth_response" | sed '$d')
  if [ "$${auth_http:0:1}" != "2" ]; then
    die "Authentication failed (HTTP $auth_http)"
  fi
  jwt=$(echo "$auth_body" | json_get "['access_token']")
  auth_body=""
  auth_response=""
  log "Authenticated successfully"

  local vault="$VAULT_ID_INPUT"
  if [ -n "$vault" ]; then
    log "Using provided vault: $vault"
  else
    log "Creating vault '$VAULT_NAME_IN'..."
    local vault_response
    vault_response=$(api_call POST "/v1/vaults" "$jwt" \
      "{\"name\": \"$VAULT_NAME_IN\"}") || {
      log "Vault creation failed — looking for existing vault named '$VAULT_NAME_IN'"
      local list_response
      list_response=$(api_call GET "/v1/vaults" "$jwt") || die "Failed to list vaults"
      vault=$(echo "$list_response" | python3 -c "
import json, sys
for v in json.load(sys.stdin).get('vaults', []):
    if v['name'] == '$VAULT_NAME_IN':
        print(v['id']); sys.exit(0)
sys.exit(1)
") || die "Could not find existing vault named '$VAULT_NAME_IN'"
      log "Found existing vault: $vault"
    }
    if [ -z "$vault" ]; then
      vault=$(echo "$vault_response" | json_get "['id']")
      log "Created vault: $vault"
    fi
  fi

  log "Creating agent '$AGENT_NAME_IN'..."
  local agent_response agent_id agent_key
  agent_response=$(api_call POST "/v1/agents" "$jwt" \
    "{\"name\": \"$AGENT_NAME_IN\", \"vault_ids\": [\"$vault\"]}") || die "Failed to create agent"

  agent_id=$(echo "$agent_response" | json_get "['agent']['id']")
  agent_key=$(echo "$agent_response" | json_get "['api_key']")
  if [ -z "$agent_key" ] || [ "$agent_key" = "None" ]; then
    die "Agent created but no API key returned"
  fi
  log "Created agent: $agent_id"

  log "Creating access policy (path: $POLICY_PATH_IN)..."
  api_call POST "/v1/vaults/$vault/policies" "$jwt" \
    "{\"secret_path_pattern\": \"$POLICY_PATH_IN\", \"principal_type\": \"agent\", \"principal_id\": \"$agent_id\", \"permissions\": [\"read\", \"write\"]}" \
    > /dev/null || die "Failed to create policy"
  log "Policy created"

  mkdir -p "$STATE_DIR"
  python3 - "$STATE_FILE" "$vault" "$agent_id" "$agent_key" << 'PYEOF'
import json, sys
state = {
    "vault_id": sys.argv[2],
    "agent_id": sys.argv[3],
    "agent_api_key": sys.argv[4]
}
with open(sys.argv[1], "w") as f:
    json.dump(state, f, indent=2)
PYEOF
  chmod 600 "$STATE_FILE"

  jwt=""
  unset jwt

  log "Bootstrap complete — credentials saved to $STATE_FILE"
  log "  Vault:  $vault"
  log "  Agent:  $agent_id"
}

write_mcp_config() {
  local target_path="$1" label="$2" tmp_file="$3"
  target_path=$(eval echo "$target_path")
  local target_dir
  target_dir=$(dirname "$target_path")
  [ -d "$target_dir" ] || mkdir -p "$target_dir"

  if [ -f "$target_path" ]; then
    log "Merging 1Claw MCP server into existing $label config at $target_path"
    python3 - "$target_path" "$tmp_file" << 'PYEOF'
import json, sys
target_path = sys.argv[1]
new_config_path = sys.argv[2]
try:
    with open(target_path) as f:
        existing = json.load(f)
except (json.JSONDecodeError, FileNotFoundError):
    existing = {}
with open(new_config_path) as f:
    new_server = json.load(f)
existing.setdefault("mcpServers", {}).update(new_server.get("mcpServers", {}))
with open(target_path, "w") as f:
    json.dump(existing, f, indent=2)
PYEOF
  else
    log "Writing $label MCP config to $target_path"
    cp "$tmp_file" "$target_path"
  fi

  chmod 600 "$target_path"
  log "$label MCP config ready at $target_path"
}

if [ "$BOOTSTRAP_MODE" = "true" ]; then
  bootstrap
fi

# Scrub the human bootstrap key from both the local var and the inherited env,
# so downstream processes (shells, AI agents) cannot read it from this script's
# /proc/<pid>/environ or from their own inherited environment.
HUMAN_KEY=""
unset HUMAN_KEY
unset _ONECLAW_HUMAN_API_KEY

# Bootstrap runs first and writes creds to the state file; load them now.
if [ -z "$API_TOKEN" ] && [ -f "$STATE_FILE" ]; then
  log "Loading credentials from bootstrap state"
  API_TOKEN=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['agent_api_key'])")
  VAULT_ID=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['vault_id'])")
fi

if [ -z "$API_TOKEN" ] || [ -z "$VAULT_ID" ]; then
  log "WARNING: No API token or vault ID available — skipping MCP config"
  log "Provide api_token + vault_id, or set human_api_key/master_api_key"
  exit 0
fi

MCP_CONFIG_TMP=$(mktemp)
trap 'rm -f "$MCP_CONFIG_TMP"' EXIT

python3 - "$API_TOKEN" "$VAULT_ID" "${MCP_HOST}" > "$MCP_CONFIG_TMP" << 'PYEOF'
import json, sys
config = {
    "mcpServers": {
        "1claw": {
            "url": sys.argv[3],
            "headers": {
                "Authorization": "Bearer " + sys.argv[1],
                "X-Vault-ID": sys.argv[2]
            }
        }
    }
}
print(json.dumps(config, indent=2))
PYEOF

if [ "${INSTALL_CURSOR_CONFIG}" = "true" ]; then
  write_mcp_config "${CURSOR_CONFIG_PATH}" "Cursor" "$MCP_CONFIG_TMP"
fi

if [ "${INSTALL_CLAUDE_CONFIG}" = "true" ]; then
  write_mcp_config "${CLAUDE_CONFIG_PATH}" "Claude Code" "$MCP_CONFIG_TMP"
fi

log "1Claw setup complete"
