#!/bin/sh
# POSIX sh, because the launcher image is Alpine with no bash.
#
# Creates the OpenShell sandbox of a workspace and deletes it on stop.
# main.tf runs it inline with sh -c in the launcher Pod, and passes the
# values as environment variables.
set -eu

mkdir -p "$HOME/.config/openshell/gateways/coder/mtls"
cp /openshell-tls/ca.crt /openshell-tls/tls.crt /openshell-tls/tls.key "$HOME/.config/openshell/gateways/coder/mtls/"
openshell gateway add "$OPENSHELL_GATEWAY_URL" --local --name coder > /dev/null
printf '%s' "$SANDBOX_POLICY" > "$HOME/policy.yaml"

# Each start creates a new sandbox. Remove one that a launcher left when it
# did not shut down cleanly.
openshell sandbox delete "$SANDBOX_NAME" > /dev/null 2>&1 || true

# create runs in the background, so the TERM trap runs at once, even while
# a create waits for compute.
pid=""
cleanup() {
  if [ -n "$pid" ]; then
    kill "$pid" 2> /dev/null || true
    wait "$pid" 2> /dev/null || true
  fi
  echo "deleting sandbox $SANDBOX_NAME"
  openshell sandbox delete "$SANDBOX_NAME" || true
  exit 0
}
trap cleanup TERM INT

create() {
  openshell sandbox create \
    --name "$SANDBOX_NAME" \
    --from "$SANDBOX_IMAGE" \
    --cpu "$SANDBOX_CPU" \
    --memory "$SANDBOX_MEMORY" \
    --policy "$HOME/policy.yaml" \
    --driver-config-json "$SANDBOX_DRIVER_CONFIG" \
    --label "coder-workspace-id=$CODER_WORKSPACE_ID" \
    --env HOME="$SANDBOX_HOME" \
    --env CODER_AGENT_URL="$CODER_AGENT_URL" \
    --env CODER_AGENT_AUTH=token \
    --env-from CODER_AGENT_TOKEN \
    --no-credential-warnings \
    --no-auto-providers \
    --detach --no-tty \
    -- sh -c "$SANDBOX_COMMAND"
}

# Retry until the sandbox starts. A create can time out, for example when
# the nodes are out of CPU. Without a retry, the agent never connects.
while true; do
  create &
  pid=$!
  if wait "$pid"; then
    pid=""
    break
  fi
  pid=""
  echo "sandbox create failed, retrying in 10 s"
  openshell sandbox delete "$SANDBOX_NAME" > /dev/null 2>&1 || true
  sleep 10 &
  wait $!
done

# Wait in the background, so the TERM trap runs at once.
while true; do
  sleep 30 &
  wait $!
done
