#!/usr/bin/env bash
# Delete the workspace service (nice-to-have; cascade from
# projectDelete already covers this).
#
# Env vars required: API, TOKEN
# Reads service id from local .railway-state/service_id if present.
. "$(dirname "$0")/lib.sh"

STATE_DIR=".railway-state"
[ ! -f "$STATE_DIR/service_id" ] && exit 0
SERVICE_ID=$(cat "$STATE_DIR/service_id")

gql "mutation { serviceDelete(id: \\\"$SERVICE_ID\\\") }" || true
