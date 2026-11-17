#!/usr/bin/env bash
# Starts the Coder agent only once the NetworkPolicy of this Pod is enforced.
# main.tf runs it inline with bash -c. Adapted from
# coder-labs/kubernetes-sandboxed in coder/registry (Apache-2.0).
#
# The VPC CNI applies a new Pod's policy a few seconds after the Pod starts,
# and in standard mode the Pod is open until then. The NetworkPolicy does not
# allow the Kubernetes API server, so a connection to it that fails proves
# the policy is in force. After start, the same check runs every 5 seconds,
# and the container stops if the API server becomes reachable. Fail closed:
# a check that prints nothing counts as reachable, and the gate opens only
# after 3 failed connections in a row, each with a 1 second timeout, so one
# slow connection cannot open it.

if [ -z "${KUBERNETES_SERVICE_HOST:-}" ] || [ -z "${KUBERNETES_SERVICE_PORT:-}" ]; then
  echo "policy gate: KUBERNETES_SERVICE_HOST is not set, so the check cannot run, exiting" >&2
  exit 1
fi

api="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT/"

api_open() {
  r=$(curl -sk -o /dev/null --noproxy '*' --connect-timeout 1 -m 2 -w '%{http_code} %{time_connect}' "$api" 2> /dev/null)
  [ -z "$r" ] && return 0
  awk -v t="${r#* }" 'BEGIN { exit !(t + 0 > 0) }'
}

closed=0
deadline=$((SECONDS + 60))
while [ "$closed" -lt 3 ]; do
  if api_open; then
    closed=0
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "policy gate: NetworkPolicy is not enforced after 60 s, exiting" >&2
      exit 1
    fi
    sleep 0.25
  else
    closed=$((closed + 1))
  fi
done
echo "policy gate: NetworkPolicy enforced after $SECONDS s" >&2

# The agent runs as PID 1 (exec below), so the re-check runs in the
# background.
(
  while sleep 5; do
    if api_open; then
      echo "policy gate: NetworkPolicy is no longer enforced, stopping" >&2
      kill -TERM 1
      sleep 2
      kill -KILL -1
      exit 1
    fi
  done
) &

exec /usr/local/bin/coder agent
