#!/usr/bin/env bash
# Runs a standalone OpenShell gateway in the workspace Pod and creates the
# workspace's sandbox with the gateway's Docker driver. main.tf runs it
# inline with bash -c in the launcher container and passes the values as
# environment variables. The Docker daemon runs in the docker container of
# the same Pod, inside the Pod's Kata VM.
set -euo pipefail

export DOCKER_HOST="unix:///var/run/docker/docker.sock"
export OPENSHELL_TELEMETRY_ENABLED=false
state="$HOME/state"
# HOME is an emptyDir that outlives a restart of this container. Start
# with a new gateway every time, because the old sandbox is removed below.
rm -rf "$state" "$HOME/tls" "$HOME/.config/openshell"
mkdir -p "$state"

# Start the sandbox only once the Pod's NetworkPolicy is in force, that is
# once a TCP connection to the Kubernetes API server fails. The supervisor
# uses the Pod network for the allowed hosts.
api="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT/"
api_open() {
  r=$(curl -sk -o /dev/null --noproxy '*' --connect-timeout 0.3 -m 1 -w '%{http_code} %{time_connect}' "$api" 2> /dev/null) || true
  [ -z "$r" ] && return 0
  awk -v t="${r#* }" 'BEGIN { exit !(t + 0 > 0) }'
}
if [ "$NETWORK_POLICY_GATE" = true ]; then
  i=0
  while api_open; do
    i=$((i + 1))
    if [ "$i" -ge 240 ]; then
      echo "NetworkPolicy is not enforced" >&2
      exit 1
    fi
    sleep 0.25
  done
fi

until docker info > /dev/null 2>&1; do sleep 0.2; done

# A new gateway has no record of the sandbox of an earlier Pod or launcher,
# so remove its containers and runtime volumes.
old=$(docker ps -aq --filter label=openshell.ai/managed-by=openshell)
if [ -n "$old" ]; then
  # shellcheck disable=SC2086
  docker rm -f $old > /dev/null
fi
docker volume ls -q --filter label=openshell.ai/managed-by=openshell | xargs -r docker volume rm > /dev/null

# The home is a Docker volume on the Docker disk. The labels let the
# gateway attach it. The workspace user owns it.
if ! docker volume inspect coder-home > /dev/null 2>&1; then
  docker volume create \
    --label openshell.ai/sandbox-attachable=true \
    --label openshell.ai/sandbox-attachable-workspace=default \
    coder-home > /dev/null
fi
docker image inspect "$SANDBOX_IMAGE" > /dev/null 2>&1 || docker pull -q "$SANDBOX_IMAGE"
docker run --rm --network none -u 0 --entrypoint chown -v coder-home:/h "$SANDBOX_IMAGE" "$SANDBOX_UID:$SANDBOX_UID" /h

# The gateway listens on loopback with mTLS. Only this container can reach
# it: the sandbox has no network.
tls="$HOME/tls"
openshell-gateway generate-certs --output-dir "$tls" --server-san host.openshell.internal > /dev/null 2>&1
cat > "$HOME/gateway.toml" << 'EOF'
[openshell]
version = 2

[openshell.drivers.docker]
allow_driver_config = true
socket_path = "/var/run/docker/docker.sock"
EOF
OPENSHELL_LOCAL_TLS_DIR="$tls" XDG_STATE_HOME="$state" \
  openshell-gateway --config "$HOME/gateway.toml" --compute-driver docker --log-level warn &
gateway=$!
trap 'kill "$gateway" 2> /dev/null || true' EXIT

mtls="$HOME/.config/openshell/gateways/local/mtls"
mkdir -p "$mtls"
cp "$tls/ca.crt" "$tls/client/tls.crt" "$tls/client/tls.key" "$mtls/"
openshell gateway add https://127.0.0.1:17670 --local --name local > /dev/null
until openshell sandbox list > /dev/null 2>&1; do
  kill -0 "$gateway" || exit 1
  sleep 0.2
done
printf '%s' "$SANDBOX_POLICY" > "$HOME/policy.yaml"

# The sandbox has only loopback, and the supervisor makes each outbound
# connection. CODER_AGENT_DERP_ONLY tells the agent to connect through the
# Coder DERP relay and not wait for a network interface.
until openshell sandbox create \
  --name "$SANDBOX_NAME" \
  --from "$SANDBOX_IMAGE" \
  --policy "$HOME/policy.yaml" \
  --driver-config-json "$SANDBOX_DRIVER_CONFIG" \
  --env HOME="$SANDBOX_HOME" \
  --env CODER_AGENT_URL="$CODER_AGENT_URL" \
  --env CODER_AGENT_AUTH=token \
  --env CODER_AGENT_DERP_ONLY=true \
  --env-from CODER_AGENT_TOKEN \
  --no-credential-warnings \
  --no-auto-providers \
  --detach --no-tty \
  -- sh -c "$SANDBOX_COMMAND"; do
  echo "sandbox create failed, retrying in 5 s" >&2
  openshell sandbox delete "$SANDBOX_NAME" > /dev/null 2>&1 || true
  sleep 5
done

# The gateway owns the sandbox. If it exits, so does this container, and
# the restart creates a new sandbox. The NetworkPolicy check runs again
# every 5 s.
while kill -0 "$gateway" 2> /dev/null; do
  if [ "$NETWORK_POLICY_GATE" = true ] && api_open; then
    echo "NetworkPolicy is no longer enforced, deleting the sandbox" >&2
    openshell sandbox delete "$SANDBOX_NAME" || true
    exit 1
  fi
  sleep 5
done
exit 1
