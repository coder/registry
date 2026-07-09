#!/usr/bin/env bash
# Delete the Railway project for this workspace. Looks up by name so
# we do not need state files to be present at destroy time.
#
# Env vars required: API, TOKEN, PROJECT_NAME
. "$(dirname "$0")/lib.sh"

PROJECT_ID=$(lookup_project_id)
if [ -z "$PROJECT_ID" ]; then
  echo "Project $PROJECT_NAME not found, nothing to delete"
  exit 0
fi

echo "Deleting project $PROJECT_NAME ($PROJECT_ID)"
gql "mutation { projectDelete(id: \\\"$PROJECT_ID\\\") }" || true
