#!/bin/bash
set -euo pipefail

LOG_PREFIX="[1claw-provision]"
log() { echo "$LOG_PREFIX $*"; }
die() {
  log "ERROR: $*" >&2
  exit 1
}

API_URL="${BASE_URL}"
MASTER_KEY="${MASTER_API_KEY}"
WORKSPACE_ID="${WORKSPACE_ID}"
WORKSPACE_NAME="${WORKSPACE_NAME}"
VAULT_NAME="${VAULT_NAME}"
AGENT_NAME="${AGENT_NAME}"
POLICY_PATH="${POLICY_PATH}"
TOKEN_TTL_SECS="${TOKEN_TTL_SECONDS}"
STATE_FILE="${STATE_FILE}"

[ -n "$MASTER_KEY" ] || die "master_api_key is required"

if [ -f "$STATE_FILE" ]; then
  log "Provision state already exists at $STATE_FILE — skipping"
  exit 0
fi

api_call() {
  local method="$1" path="$2" token="$3" body="$${4:-}"
  local response http_code body_out

  response=$(curl -sf -w "\n%%{http_code}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $token" \
    $${body:+-d "$body"} \
    -X "$method" "$API_URL$path" 2>&1) || {
    log "curl failed: $method $path"
    return 1
  }

  http_code=$(echo "$response" | tail -1)
  body_out=$(echo "$response" | sed '$d')

  if [ "$${http_code:0:1}" != "2" ]; then
    log "API $method $path => HTTP $http_code"
    log "Body: $body_out"
    return 1
  fi
  echo "$body_out"
}

json_get() { python3 -c "import json,sys; print(json.load(sys.stdin)$1)"; }

# --- Step 1: Exchange master key for JWT ---
log "Authenticating..."
AUTH=$(curl -sf -w "\n%%{http_code}" \
  -H "Content-Type: application/json" \
  -d "{\"api_key\": \"$MASTER_KEY\"}" \
  "$API_URL/v1/auth/api-key-token" 2>&1) || die "Auth request failed"

AUTH_HTTP=$(echo "$AUTH" | tail -1)
AUTH_BODY=$(echo "$AUTH" | sed '$d')
[ "$${AUTH_HTTP:0:1}" = "2" ] || die "Auth failed (HTTP $AUTH_HTTP): $AUTH_BODY"

JWT=$(echo "$AUTH_BODY" | json_get "['access_token']")
log "Authenticated"

# --- Step 2: Resolve or create vault ---
log "Creating vault '$VAULT_NAME'..."
VAULT_ID=""
VAULT_RESP=$(api_call POST "/v1/vaults" "$JWT" \
  "{\"name\": \"$VAULT_NAME\", \"description\": \"Auto-provisioned for Coder workspace $WORKSPACE_NAME ($WORKSPACE_ID)\"}") && {
  VAULT_ID=$(echo "$VAULT_RESP" | json_get "['id']")
  log "Created vault: $VAULT_ID"
} || {
  log "Vault creation failed — searching for existing '$VAULT_NAME'"
  LIST_RESP=$(api_call GET "/v1/vaults" "$JWT") || die "Cannot list vaults"
  VAULT_ID=$(echo "$LIST_RESP" | python3 -c "
import json, sys
for v in json.load(sys.stdin).get('vaults', []):
    if v['name'] == '$VAULT_NAME':
        print(v['id']); sys.exit(0)
sys.exit(1)
") || die "No vault named '$VAULT_NAME' found"
  log "Using existing vault: $VAULT_ID"
}

# --- Step 3: Create agent scoped to this vault ---
AGENT_PAYLOAD=$(python3 -c "
import json, sys
payload = {
    'name': '$AGENT_NAME',
    'vault_ids': ['$VAULT_ID'],
    'description': 'Coder workspace $WORKSPACE_NAME ($WORKSPACE_ID)'
}
ttl = int('$TOKEN_TTL_SECS') if '$TOKEN_TTL_SECS' and '$TOKEN_TTL_SECS' != '0' else None
if ttl:
    payload['token_ttl_seconds'] = ttl
print(json.dumps(payload))
")

log "Creating agent '$AGENT_NAME' (ttl=$${TOKEN_TTL_SECS}s)..."
AGENT_RESP=$(api_call POST "/v1/agents" "$JWT" "$AGENT_PAYLOAD") || die "Failed to create agent"

AGENT_ID=$(echo "$AGENT_RESP" | json_get "['agent']['id']")
AGENT_KEY=$(echo "$AGENT_RESP" | json_get "['api_key']")

[ -n "$AGENT_KEY" ] && [ "$AGENT_KEY" != "None" ] || die "Agent created but no API key returned"
log "Created agent: $AGENT_ID"

# --- Step 4: Create access policy ---
log "Creating policy (path: $POLICY_PATH)..."
api_call POST "/v1/vaults/$VAULT_ID/policies" "$JWT" \
  "{\"secret_path_pattern\": \"$POLICY_PATH\", \"principal_type\": \"agent\", \"principal_id\": \"$AGENT_ID\", \"permissions\": [\"read\", \"write\"]}" \
  > /dev/null || die "Failed to create policy"
log "Policy created"

# --- Step 5: Exchange agent key for a scoped JWT ---
log "Exchanging agent key for scoped token..."
TOKEN_RESP=$(curl -sf -w "\n%%{http_code}" \
  -H "Content-Type: application/json" \
  -d "{\"agent_id\": \"$AGENT_ID\", \"api_key\": \"$AGENT_KEY\"}" \
  "$API_URL/v1/auth/agent-token" 2>&1) || die "Token exchange failed"

TOKEN_HTTP=$(echo "$TOKEN_RESP" | tail -1)
TOKEN_BODY=$(echo "$TOKEN_RESP" | sed '$d')
[ "$${TOKEN_HTTP:0:1}" = "2" ] || die "Token exchange failed (HTTP $TOKEN_HTTP)"

SCOPED_TOKEN=$(echo "$TOKEN_BODY" | json_get "['access_token']")
log "Got scoped token"

# --- Step 6: Write state file ---
mkdir -p "$(dirname "$STATE_FILE")"
python3 - "$STATE_FILE" "$VAULT_ID" "$AGENT_ID" "$AGENT_KEY" "$SCOPED_TOKEN" "$WORKSPACE_ID" << 'PYEOF'
import json, sys
state = {
    "vault_id": sys.argv[2],
    "agent_id": sys.argv[3],
    "agent_api_key": sys.argv[4],
    "scoped_token": sys.argv[5],
    "workspace_id": sys.argv[6]
}
with open(sys.argv[1], "w") as f:
    json.dump(state, f, indent=2)
PYEOF
chmod 600 "$STATE_FILE"

log "Provision complete"
log "  Vault:   $VAULT_ID"
log "  Agent:   $AGENT_ID"
log "  Key:     $${AGENT_KEY:0:12}..."
