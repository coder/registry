#!/usr/bin/env bash
# Delete the coder-managed project token and the RAILWAY_TOKEN env var.
# Safe to run when the project is already gone (no-op in that case).
#
# Env vars required: API, TOKEN, PROJECT_NAME
. "$(dirname "$0")/lib.sh"

TOKEN_NAME='coder-managed'

PE=$(lookup_project_and_env)
PROJ=$(echo "$PE" | awk '{print $1}')
ENV=$(echo "$PE" | awk '{print $2}')
if [ -z "$PROJ" ]; then
  echo "Project $PROJECT_NAME already gone, nothing to clean up."
  exit 0
fi

DETAIL=$(gql "{ project(id: \\\"$PROJ\\\") { services { edges { node { id name } } } } }" || echo '')
SVC=$(echo "$DETAIL" | grep -o '"id":"[^"]*","name":"workspace"' \
  | sed 's/.*"id":"\([^"]*\)".*/\1/' | head -1 || true)

# Delete the project token if it exists.
EXISTING=$(gql "{ projectTokens(projectId: \\\"$PROJ\\\") { edges { node { id name } } } }" || echo '')
TOKEN_ID=$(echo "$EXISTING" | grep -o '"id":"[^"]*","name":"'"$TOKEN_NAME"'"' \
  | sed 's/.*"id":"\([^"]*\)".*/\1/' | head -1 || true)
if [ -n "$TOKEN_ID" ]; then
  gql "mutation { projectTokenDelete(id: \\\"$TOKEN_ID\\\") }" > /dev/null || true
fi

# Delete the RAILWAY_TOKEN env var.
if [ -n "$SVC" ] && [ -n "$ENV" ]; then
  gql "mutation { variableDelete(input: { projectId: \\\"$PROJ\\\", serviceId: \\\"$SVC\\\", environmentId: \\\"$ENV\\\", name: \\\"RAILWAY_TOKEN\\\" }) }" > /dev/null || true
fi
