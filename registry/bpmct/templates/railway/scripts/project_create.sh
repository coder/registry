#!/usr/bin/env bash
# Create (or look up) the Railway project for this workspace.
# Idempotent: reuses an existing project of the same name if found.
# Writes project_id and environment_id to $STATE_DIR.
#
# Env vars required:
#   API, TOKEN, PROJECT_NAME, STATE_DIR
set -euo pipefail
. "$(dirname "$0")/lib.sh"

mkdir -p "$STATE_DIR"

# If a project with this name already exists (prior attempt succeeded
# but TF lost the response), reuse it instead of creating a duplicate.
EXISTING=$(lookup_project_and_env)
if [ -n "$EXISTING" ]; then
  EXISTING_PID=$(echo "$EXISTING" | awk '{print $1}')
  EXISTING_EID=$(echo "$EXISTING" | awk '{print $2}')
  if [ -n "$EXISTING_PID" ]; then
    echo "Project $PROJECT_NAME already exists: $EXISTING_PID"
    echo "$EXISTING_PID" > "$STATE_DIR/project_id"
    echo "$EXISTING_EID" > "$STATE_DIR/environment_id"
    exit 0
  fi
fi

# Retry projectCreate. Railway projectCreate can take 30s+ under load,
# exceeding edge timeouts (504). A 504 may still have created the
# project, so we look up by name before each retry.
BACKOFF=5
for ATTEMPT in 1 2 3 4 5; do
  echo "projectCreate attempt $ATTEMPT/5"
  HTTP_CODE=$(curl -s --max-time 90 -o /tmp/proj-resp.$$ -w '%{http_code}' -X POST "$API" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -d "{\"query\": \"mutation(\$input: ProjectCreateInput!) { projectCreate(input: \$input) { id environments { edges { node { id name } } } } }\", \"variables\": { \"input\": { \"name\": \"$PROJECT_NAME\" } } }" || echo '000')
  RESP=$(cat /tmp/proj-resp.$$ 2> /dev/null || echo '')
  rm -f /tmp/proj-resp.$$
  echo "HTTP $HTTP_CODE"
  echo "$RESP" | head -c 500
  echo

  # Success path: HTTP 200 with projectCreate.id in response.
  if [ "$HTTP_CODE" = "200" ] && echo "$RESP" | grep -q '"projectCreate":{"id":"'; then
    echo "$RESP" | sed 's/.*"projectCreate":{"id":"\([^"]*\)".*/\1/' > "$STATE_DIR/project_id"
    echo "$RESP" | sed 's/.*"node":{"id":"\([^"]*\)".*/\1/' > "$STATE_DIR/environment_id"
    echo "projectCreate succeeded"
    exit 0
  fi

  # On any non-success, check whether the project got created anyway
  # (504 or client timeout but the mutation still landed).
  AFTER=$(lookup_project_and_env)
  if [ -n "$AFTER" ]; then
    AFTER_PID=$(echo "$AFTER" | awk '{print $1}')
    AFTER_EID=$(echo "$AFTER" | awk '{print $2}')
    if [ -n "$AFTER_PID" ]; then
      echo "Found project created by attempt $ATTEMPT despite error: $AFTER_PID"
      echo "$AFTER_PID" > "$STATE_DIR/project_id"
      echo "$AFTER_EID" > "$STATE_DIR/environment_id"
      exit 0
    fi
  fi

  echo "projectCreate attempt $ATTEMPT failed (HTTP $HTTP_CODE), retrying in ${BACKOFF}s..."
  [ "$ATTEMPT" -lt 5 ] && sleep "$BACKOFF"
  BACKOFF=$((BACKOFF * 2))
done

echo "FATAL: projectCreate failed after 5 attempts"
exit 1
