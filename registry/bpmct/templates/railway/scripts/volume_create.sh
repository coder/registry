#!/usr/bin/env bash
# Create the persistent volume for the workspace.
#
# CRITICAL: This must run before any deployment activity on the
# service. Railway rejects volumeCreate on services that have had
# deployments. The pure-GraphQL ordering guarantees this.
#
# Env vars required: API, TOKEN, PROJECT_NAME, STATE_DIR
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

# Idempotent: if a workspace-volume already exists in this project,
# reuse it instead of creating a duplicate.
VOLUMES=$(gql "{ project(id: \\\"$PROJECT_ID\\\") { volumes { edges { node { id name } } } } }")
EXISTING_VOL=$(echo "$VOLUMES" | grep -o '"id":"[^"]*","name":"workspace-volume"' \
  | sed 's/.*"id":"\([^"]*\)".*/\1/' | head -1 || true)
if [ -n "$EXISTING_VOL" ]; then
  echo "Volume already exists: $EXISTING_VOL"
  exit 0
fi

RESP=$(gql "mutation { volumeCreate(input: { projectId: \\\"$PROJECT_ID\\\", serviceId: \\\"$SERVICE_ID\\\", environmentId: \\\"$ENV_ID\\\", mountPath: \\\"/home/coder\\\" }) { id } }")
echo "$RESP"
if echo "$RESP" | grep -q '"errors"'; then
  echo "FATAL: volumeCreate failed"
  exit 1
fi

echo "$RESP" | sed 's/.*"volumeCreate":{"id":"\([^"]*\)".*/\1/' > "$STATE_DIR/volume_id"
