#!/usr/bin/env bash
# Create (or look up) the "workspace" service inside the Railway
# project. Idempotent. Writes service_id to $STATE_DIR.
#
# Env vars required: API, TOKEN, PROJECT_NAME, STATE_DIR
set -euo pipefail
. "$(dirname "$0")/lib.sh"

# Read project_id from state (same apply) or fall back to API lookup.
PROJECT_ID=""
[ -f "$STATE_DIR/project_id" ] && PROJECT_ID=$(cat "$STATE_DIR/project_id")
if [ -z "$PROJECT_ID" ]; then
  PROJECT_ID=$(lookup_project_id)
fi
[ -z "$PROJECT_ID" ] && {
  echo "FATAL: project not found"
  exit 1
}

# If a "workspace" service already exists, reuse it.
EXISTING=$(gql "{ project(id: \\\"$PROJECT_ID\\\") { services { edges { node { id name } } } } }")
EXISTING_SVC=$(echo "$EXISTING" | grep -o '"id":"[^"]*","name":"workspace"' \
  | sed 's/.*"id":"\([^"]*\)".*/\1/' | head -1 || true)
if [ -n "$EXISTING_SVC" ]; then
  echo "Service already exists: $EXISTING_SVC"
  mkdir -p "$STATE_DIR"
  echo "$EXISTING_SVC" > "$STATE_DIR/service_id"
  exit 0
fi

# Retry serviceCreate. Railway can return "Not Authorized" briefly
# after projectCreate due to auth propagation delay.
RESP=""
for ATTEMPT in 1 2 3 4 5; do
  RESP=$(gql "mutation { serviceCreate(input: { name: \\\"workspace\\\", projectId: \\\"$PROJECT_ID\\\" }) { id } }")
  echo "$RESP"
  if echo "$RESP" | grep -q '"serviceCreate"'; then break; fi
  echo "serviceCreate attempt $ATTEMPT failed, retrying in 3s..."
  [ "$ATTEMPT" -lt 5 ] && sleep 3
done
if ! echo "$RESP" | grep -q '"serviceCreate"'; then
  echo "FATAL: serviceCreate failed"
  exit 1
fi

mkdir -p "$STATE_DIR"
echo "$RESP" | sed 's/.*"serviceCreate":{"id":"\([^"]*\)".*/\1/' > "$STATE_DIR/service_id"
