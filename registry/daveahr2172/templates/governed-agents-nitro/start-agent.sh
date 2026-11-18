#!/usr/bin/env bash
# Starts the Coder agent after a startup readiness check of this Pod's
# NetworkPolicy. main.tf runs it inline with bash -c. Adapted from
# coder-labs/kubernetes-sandboxed in coder/registry (Apache-2.0).
#
# This script is a readiness check and a watchdog. It is not the security
# boundary. It runs as the same user as the agent, so a process in the
# workspace can kill it. Enforcement must come from outside the Pod: on EKS
# Auto Mode, set networkPolicy = DefaultDeny on the agent NodeClass, so a
# Pod has no egress until its NetworkPolicy allows it and stays closed if
# the policy is deleted. To stop a running workspace from outside, use
# coder stop (see README.md).
#
# The NetworkPolicy does not allow the Kubernetes API server, so failed
# connections to it show that the policy is in force. The check opens after
# 3 failed connections in a row, each with a 1 second timeout. A check that
# prints nothing counts as reachable. Any other failure to connect, for
# example an API server outage, also counts as closed, which is why the
# check alone does not prove enforcement. After start, the same check runs
# every 5 seconds and stops the container if the API server becomes
# reachable.

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
