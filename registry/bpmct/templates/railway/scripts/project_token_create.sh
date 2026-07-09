#!/usr/bin/env bash
# Provision a project-scoped Railway token (named "coder-managed") and
# upsert it as RAILWAY_TOKEN on the workspace service. The token is
# rotated on every apply because Railway does not expose existing
# token values after creation.
#
# Env vars required:
#   API, TOKEN, PROJECT_NAME, STATE_DIR
set -euo pipefail
. "$(dirname "$0")/lib.sh"

TOKEN_NAME='coder-managed'

PROJECT_ID=""
SERVICE_ID=""
ENV_ID=""
load_state

if [ -z "$PROJECT_ID" ] || [ -z "$SERVICE_ID" ] || [ -z "$ENV_ID" ]; then
  PE=$(lookup_project_and_env)
  PROJECT_ID=$(echo "$PE" | awk '{print $1}')
  ENV_ID=$(echo "$PE" | awk '{print $2}')
  [ -z "$PROJECT_ID" ] && {
    echo "FATAL: project $PROJECT_NAME not found" >&2
    exit 1
  }
  DETAIL=$(gql "{ project(id: \\\"$PROJECT_ID\\\") { services { edges { node { id name } } } } }")
  SERVICE_ID=$(echo "$DETAIL" | grep -o '"id":"[^"]*","name":"workspace"' \
    | sed 's/.*"id":"\([^"]*\)".*/\1/' | head -1 || true)
fi
[ -z "$SERVICE_ID" ] || [ -z "$ENV_ID" ] && {
  echo "FATAL: service or env not found" >&2
  exit 1
}

# Project tokens cannot be retrieved by value after creation. Delete
# any existing token with our managed name so we can mint a fresh one.
EXISTING=$(gql "{ projectTokens(projectId: \\\"$PROJECT_ID\\\") { edges { node { id name } } } }")
OLD_ID=$(echo "$EXISTING" | grep -o '"id":"[^"]*","name":"'"$TOKEN_NAME"'"' \
  | sed 's/.*"id":"\([^"]*\)".*/\1/' | head -1 || true)
if [ -n "$OLD_ID" ]; then
  echo "Removing existing project token $OLD_ID"
  gql "mutation { projectTokenDelete(id: \\\"$OLD_ID\\\") }" > /dev/null || true
fi

# Create the project-scoped token.
RESP=$(gql "mutation { projectTokenCreate(input: { projectId: \\\"$PROJECT_ID\\\", environmentId: \\\"$ENV_ID\\\", name: \\\"$TOKEN_NAME\\\" }) }")
if echo "$RESP" | grep -q '"errors"'; then
  echo "FATAL: projectTokenCreate failed: $RESP" >&2
  exit 1
fi
NEW_TOKEN=$(echo "$RESP" | sed 's/.*"projectTokenCreate":"\([^"]*\)".*/\1/')
if [ -z "$NEW_TOKEN" ] || [ "$NEW_TOKEN" = "$RESP" ]; then
  echo "FATAL: could not parse projectTokenCreate response: $RESP" >&2
  exit 1
fi

# Upsert RAILWAY_TOKEN on the workspace service with retry.
# skipDeploys: true avoids triggering a Railway redeploy on the
# variable change. The subsequent serviceConnect (or already-in-flight
# deploy) picks up the new value.
UPSERT_OK=""
for ATTEMPT in 1 2 3 4 5; do
  UPSERT=$(curl -s --max-time 60 -X POST "$API" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -d "{\"query\": \"mutation { variableUpsert(input: { projectId: \\\"$PROJECT_ID\\\", serviceId: \\\"$SERVICE_ID\\\", environmentId: \\\"$ENV_ID\\\", name: \\\"RAILWAY_TOKEN\\\", value: \\\"$NEW_TOKEN\\\", skipDeploys: true }) }\"}" || true)
  if echo "$UPSERT" | grep -q '"variableUpsert":true'; then
    UPSERT_OK=1
    break
  fi
  echo "variableUpsert RAILWAY_TOKEN attempt $ATTEMPT failed, retrying..." >&2
  [ "$ATTEMPT" -lt 5 ] && sleep 5
done
if [ -z "$UPSERT_OK" ]; then
  echo "FATAL: variableUpsert RAILWAY_TOKEN failed after 5 attempts" >&2
  exit 1
fi
echo "Provisioned project-scoped Railway token and set RAILWAY_TOKEN env var."
