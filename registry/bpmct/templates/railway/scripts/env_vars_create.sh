#!/usr/bin/env bash
# Upsert the three required env vars on the workspace service:
# CODER_INIT_SCRIPT_B64, CODER_AGENT_TOKEN, RAILWAY_RUN_UID.
#
# Runs BEFORE image_deploy so the first deployment already has the
# correct values. variableUpsert on a connected service would trigger
# an extra redeploy, which we explicitly avoid.
#
# Env vars required:
#   API, TOKEN, PROJECT_NAME, STATE_DIR
#   CODER_INIT_SCRIPT_B64 - base64 of agent init script
#   CODER_AGENT_TOKEN     - agent token
set -euo pipefail
. "$(dirname "$0")/lib.sh"

PROJECT_ID=""
SERVICE_ID=""
ENV_ID=""
load_state

if [ -z "$PROJECT_ID" ] || [ -z "$SERVICE_ID" ] || [ -z "$ENV_ID" ]; then
  PROJECT_ID=$(lookup_project_id)
  [ -z "$PROJECT_ID" ] && {
    echo "FATAL: project not found"
    exit 1
  }
  SE=$(lookup_service_and_env "$PROJECT_ID")
  SERVICE_ID=$(echo "$SE" | awk '{print $1}')
  ENV_ID=$(echo "$SE" | awk '{print $2}')
fi
[ -z "$SERVICE_ID" ] || [ -z "$ENV_ID" ] && {
  echo "FATAL: service/env not found"
  exit 1
}

# Helper: upsert a single variable with retry. Railway's
# variableUpsert has been observed taking 60s+ under load and
# returning 504 at the edge with no body, which would otherwise
# surface as curl exit 28 and abort the script under set -e.
#
# skipDeploys: true tells Railway to set the value without triggering
# a redeploy. We always rely on the subsequent serviceConnect to
# trigger the actual deployment, so the deploy-on-variable-change
# behavior is unwanted and racy:
#   - On a freshly-disconnected service it fails with
#     "Cannot redeploy without a snapshot".
#   - During the first second after a cancel it fails with
#     "Cannot redeploy yet, please wait for the original
#     deployment to finish building".
upsert_var() {
  local name="$1" value="$2"
  local attempt resp
  for attempt in 1 2 3 4 5; do
    resp=$(curl -s --max-time 60 -X POST "$API" \
      -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' \
      -d "{\"query\": \"mutation { variableUpsert(input: { projectId: \\\"$PROJECT_ID\\\", serviceId: \\\"$SERVICE_ID\\\", environmentId: \\\"$ENV_ID\\\", name: \\\"$name\\\", value: \\\"$value\\\", skipDeploys: true }) }\"}" || true)
    if echo "$resp" | grep -q '"variableUpsert":true'; then
      return 0
    fi
    echo "variableUpsert $name attempt $attempt failed (resp: ${resp:0:200}), retrying..." >&2
    [ "$attempt" -lt 5 ] && sleep 5
  done
  echo "FATAL: variableUpsert $name failed after 5 attempts" >&2
  exit 1
}

upsert_var "CODER_INIT_SCRIPT_B64" "$CODER_INIT_SCRIPT_B64"
upsert_var "CODER_AGENT_TOKEN" "$CODER_AGENT_TOKEN"
upsert_var "RAILWAY_RUN_UID" "0"
