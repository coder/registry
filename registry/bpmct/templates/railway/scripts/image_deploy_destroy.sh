#!/usr/bin/env bash
# Stop the workspace by cancelling all active deployments. Runs on
# workspace stop (start_count = 0).
#
# Unlike the GraphQL variant's source_connect_destroy.sh, there is no
# `serviceDisconnect` to call: image sources are not "connected" to an
# upstream that could trigger auto-redeploys on their own. We do still
# poll briefly afterwards to catch any deploys that race with the
# env_vars destroy (which runs right after this).
#
# Env vars required: API, TOKEN, PROJECT_NAME
. "$(dirname "$0")/lib.sh"

PROJECT_ID=$(lookup_project_id)
if [ -z "$PROJECT_ID" ]; then
  echo "WARN: project not found, skipping stop"
  exit 0
fi

SE=$(lookup_service_and_env "$PROJECT_ID")
SERVICE_ID=$(echo "$SE" | awk '{print $1}')
ENV_ID=$(echo "$SE" | awk '{print $2}')
echo "service_id=$SERVICE_ID env_id=$ENV_ID"
[ -z "$SERVICE_ID" ] && {
  echo "WARN: service not found"
  exit 0
}

# Scale to zero by cancelling every recent deployment. deploymentCancel
# reliably stops deployments in any state (BUILDING/DEPLOYING/SUCCESS),
# whereas deploymentStop is unreliable for SUCCESS deployments.
DEPS=$(gql "{ deployments(first: 5, input: { serviceId: \\\"$SERVICE_ID\\\", environmentId: \\\"$ENV_ID\\\" }) { edges { node { id status } } } }")
echo "$DEPS"
for DEP_ID in $(echo "$DEPS" | sed 's/"id":"/\n/g' | grep -o '^[^"]*' | grep -E '^[0-9a-f-]+$' || true); do
  echo "Cancelling deployment $DEP_ID"
  gql "mutation { deploymentCancel(id: \\\"$DEP_ID\\\") }" || true
done

# Poll briefly for new deployments triggered by env_vars destroy that
# races with this. Cancel anything that appears. Same pattern as the
# GraphQL variant; cheap insurance.
for _ in 1 2 3 4 5 6; do
  sleep 3
  DEPS=$(gql "{ deployments(first: 5, input: { serviceId: \\\"$SERVICE_ID\\\", environmentId: \\\"$ENV_ID\\\" }) { edges { node { id status } } } }")
  for DEP_ID in $(echo "$DEPS" | sed 's/"id":"/\n/g' | grep -o '^[^"]*' | grep -E '^[0-9a-f-]+$' || true); do
    gql "mutation { deploymentCancel(id: \\\"$DEP_ID\\\") }" > /dev/null || true
  done
done
echo "Done"
