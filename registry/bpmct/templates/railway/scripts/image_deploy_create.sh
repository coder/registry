#!/usr/bin/env bash
# Set the workspace service's image source and trigger the first
# deployment. Replaces source_connect_create.sh in the GraphQL variant.
#
# Unlike `serviceConnect` (which builds from a GitHub repo on every
# start), `serviceInstanceUpdate(source: { image: "..." })` points the
# service at a pre-built container image. Railway just pulls the image
# at start, which removes the per-start Docker build (~30-60s).
#
# Sequence:
#   1. serviceInstanceUpdate(serviceId, environmentId, input: { source: { image }, ... })
#      Updates the source. By itself does NOT trigger a deploy.
#   2. serviceInstanceDeployV2(serviceId, environmentId)
#      Explicitly triggers a deploy of the current config.
#
# Env vars required:
#   API, TOKEN, PROJECT_NAME, STATE_DIR
#   WORKSPACE_IMAGE             - e.g. ghcr.io/bpmct/railway-coder-workspace:latest
#   IMAGE_REGISTRY_USERNAME     - optional, for private registries
#   IMAGE_REGISTRY_PASSWORD     - optional, for private registries
set -euo pipefail
. "$(dirname "$0")/lib.sh"

PROJECT_ID=""
SERVICE_ID=""
ENV_ID=""
load_state

if [ -z "$PROJECT_ID" ] || [ -z "$SERVICE_ID" ] || [ -z "$ENV_ID" ]; then
  PROJECT_ID=$(lookup_project_id)
  [ -z "$PROJECT_ID" ] && {
    echo "FATAL: project '$PROJECT_NAME' not found"
    exit 1
  }
  SE=$(lookup_service_and_env "$PROJECT_ID")
  SERVICE_ID=$(echo "$SE" | awk '{print $1}')
  ENV_ID=$(echo "$SE" | awk '{print $2}')
fi
[ -z "$SERVICE_ID" ] && {
  echo "FATAL: service not found"
  exit 1
}
[ -z "$ENV_ID" ] && {
  echo "FATAL: environment not found"
  exit 1
}

# Persist IDs for any later resources in this apply cycle (mirrors
# source_connect_create.sh behavior so coder_metadata etc. work).
mkdir -p "$STATE_DIR"
echo "$SERVICE_ID" > "$STATE_DIR/service_id"
echo "$ENV_ID" > "$STATE_DIR/environment_id"

[ -z "${WORKSPACE_IMAGE:-}" ] && {
  echo "FATAL: WORKSPACE_IMAGE is required"
  exit 1
}

# Build the input object inline in GraphQL. Same nested-escaping pattern
# the other scripts use: the call goes through gql() which wraps the
# string in a JSON envelope, so every quote here is double-escaped.
#
# We omit registryCredentials when not supplied so we don't send an
# empty {username: "", password: ""} block that Railway might reject.
if [ -n "${IMAGE_REGISTRY_USERNAME:-}" ] && [ -n "${IMAGE_REGISTRY_PASSWORD:-}" ]; then
  INPUT="{ source: { image: \\\"$WORKSPACE_IMAGE\\\" }, registryCredentials: { username: \\\"$IMAGE_REGISTRY_USERNAME\\\", password: \\\"$IMAGE_REGISTRY_PASSWORD\\\" } }"
else
  INPUT="{ source: { image: \\\"$WORKSPACE_IMAGE\\\" } }"
fi

RESP=$(gql "mutation { serviceInstanceUpdate(serviceId: \\\"$SERVICE_ID\\\", environmentId: \\\"$ENV_ID\\\", input: $INPUT) }")
# Redact creds if present in any error echo. The serviceInstanceUpdate
# return is just `true` on success so this is safe to log normally.
echo "serviceInstanceUpdate response: $RESP"
if ! echo "$RESP" | grep -q '"serviceInstanceUpdate":true'; then
  echo "FATAL: serviceInstanceUpdate did not return true"
  exit 1
fi

# Trigger the actual deploy. serviceInstanceUpdate by itself does not
# enqueue a build in current Railway behavior. serviceInstanceDeployV2
# returns the new deployment id on success.
DEPLOY_RESP=$(gql "mutation { serviceInstanceDeployV2(serviceId: \\\"$SERVICE_ID\\\", environmentId: \\\"$ENV_ID\\\") }")
echo "serviceInstanceDeployV2 response: $DEPLOY_RESP"
if echo "$DEPLOY_RESP" | grep -q '"errors"'; then
  echo "FATAL: serviceInstanceDeployV2 failed"
  exit 1
fi
