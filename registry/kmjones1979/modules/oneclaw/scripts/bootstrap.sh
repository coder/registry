#!/bin/bash
set -euo pipefail

LOG_PREFIX="[1claw-bootstrap]"

log() {
  echo "$LOG_PREFIX $*"
}

die() {
  log "ERROR: $*" >&2
  exit 1
}

STATE_DIR=$(eval echo "${STATE_DIR}")
STATE_FILE="$STATE_DIR/bootstrap.json"
HUMAN_KEY="${HUMAN_API_KEY}"
API_URL="${BASE_URL}"
VAULT="${VAULT_ID}"
VAULT_NAME_IN="${VAULT_NAME}"
AGENT_NAME_IN="${AGENT_NAME}"
POLICY_PATH_IN="${POLICY_PATH}"

# --- Early exit if already bootstrapped ---
if [ -f "$STATE_FILE" ]; then
  log "Bootstrap state found at $STATE_FILE — skipping provisioning"
  exit 0
fi

if [ -z "$HUMAN_KEY" ]; then
  die "human_api_key is required for bootstrap mode"
fi

api_call() {
  local method="$1"
  local path="$2"
  local token="$3"
  local body="$${4:-}"

  local response
  response=$(curl -s -w "\n%%{http_code}" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $token" \
    $${body:+-d "$body"} \
    -X "$method" "$API_URL$path" 2>&1) || {
    log "API call failed: $method $path"
    log "Response: $response"
    return 1
  }

  local http_code
  http_code=$(echo "$response" | tail -1)
  local body_out
  body_out=$(echo "$response" | sed '$d')

  if [ "$${http_code:0:1}" != "2" ]; then
    log "API error: $method $path returned HTTP $http_code"
    log "Response: $body_out"
    return 1
  fi

  echo "$body_out"
}

json_get() {
  python3 -c "import json,sys; print(json.load(sys.stdin)$1)"
}

# --- Step 1: Exchange human API key for JWT ---
log "Authenticating with 1Claw API..."
AUTH_RESPONSE=$(curl -s -w "\n%%{http_code}" \
  -H "Content-Type: application/json" \
  -d "{\"api_key\": \"$HUMAN_KEY\"}" \
  "$API_URL/v1/auth/api-key-token" 2>&1) || die "Failed to authenticate with human API key"

AUTH_HTTP=$(echo "$AUTH_RESPONSE" | tail -1)
AUTH_BODY=$(echo "$AUTH_RESPONSE" | sed '$d')

if [ "$${AUTH_HTTP:0:1}" != "2" ]; then
  die "Authentication failed (HTTP $AUTH_HTTP): $AUTH_BODY"
fi

JWT=$(echo "$AUTH_BODY" | json_get "['access_token']")
log "Authenticated successfully"

# --- Step 2: Resolve or create vault ---
if [ -n "$VAULT" ]; then
  log "Using provided vault: $VAULT"
else
  log "Creating vault '$VAULT_NAME_IN'..."
  VAULT_RESPONSE=$(api_call POST "/v1/vaults" "$JWT" \
    "{\"name\": \"$VAULT_NAME_IN\"}") || {
    log "Vault creation failed — looking for existing vault named '$VAULT_NAME_IN'"
    VAULTS_RESPONSE=$(api_call GET "/v1/vaults" "$JWT") || die "Failed to list vaults"
    VAULT=$(echo "$VAULTS_RESPONSE" | python3 -c "
import json, sys
vaults = json.load(sys.stdin).get('vaults', [])
for v in vaults:
    if v['name'] == '$VAULT_NAME_IN':
        print(v['id'])
        sys.exit(0)
sys.exit(1)
") || die "Could not find existing vault named '$VAULT_NAME_IN'"
    log "Found existing vault: $VAULT"
  }
  if [ -z "$VAULT" ]; then
    VAULT=$(echo "$VAULT_RESPONSE" | json_get "['id']")
    log "Created vault: $VAULT"
  fi
fi

# --- Step 3: Create agent ---
log "Creating agent '$AGENT_NAME_IN'..."
AGENT_RESPONSE=$(api_call POST "/v1/agents" "$JWT" \
  "{\"name\": \"$AGENT_NAME_IN\", \"vault_ids\": [\"$VAULT\"]}") || die "Failed to create agent"

AGENT_ID=$(echo "$AGENT_RESPONSE" | json_get "['agent']['id']")
AGENT_API_KEY=$(echo "$AGENT_RESPONSE" | json_get "['api_key']")

if [ -z "$AGENT_API_KEY" ] || [ "$AGENT_API_KEY" = "None" ]; then
  die "Agent created but no API key returned — check auth_method"
fi
log "Created agent: $AGENT_ID"

# --- Step 4: Create access policy ---
log "Creating access policy (path: $POLICY_PATH_IN)..."
api_call POST "/v1/vaults/$VAULT/policies" "$JWT" \
  "{\"secret_path_pattern\": \"$POLICY_PATH_IN\", \"principal_type\": \"agent\", \"principal_id\": \"$AGENT_ID\", \"permissions\": [\"read\", \"write\"]}" \
  > /dev/null || die "Failed to create policy"
log "Policy created — agent can access $POLICY_PATH_IN"

# --- Step 5: Save state ---
mkdir -p "$STATE_DIR"

python3 - "$STATE_FILE" "$VAULT" "$AGENT_ID" "$AGENT_API_KEY" << 'PYEOF'
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

log "Bootstrap complete — credentials saved to $STATE_FILE"
log "  Vault ID:  $VAULT"
log "  Agent ID:  $AGENT_ID"
log "  Agent key: $${AGENT_API_KEY:0:12}..."
