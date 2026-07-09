#!/usr/bin/env bash
# Delete the three managed env vars on stop. By this point
# image_deploy's destroy has already cancelled any active deploys, so
# these variableDelete calls cannot trigger a new redeploy.
#
# Env vars required: API, TOKEN, PROJECT_NAME
. "$(dirname "$0")/lib.sh"

PROJECT_ID=$(lookup_project_id)
[ -z "$PROJECT_ID" ] && exit 0

SE=$(lookup_service_and_env "$PROJECT_ID")
SERVICE_ID=$(echo "$SE" | awk '{print $1}')
ENV_ID=$(echo "$SE" | awk '{print $2}')
[ -z "$SERVICE_ID" ] || [ -z "$ENV_ID" ] && exit 0

for VAR_NAME in CODER_INIT_SCRIPT_B64 CODER_AGENT_TOKEN RAILWAY_RUN_UID; do
  gql "mutation { variableDelete(input: { projectId: \\\"$PROJECT_ID\\\", serviceId: \\\"$SERVICE_ID\\\", environmentId: \\\"$ENV_ID\\\", name: \\\"$VAR_NAME\\\" }) }" || true
done
