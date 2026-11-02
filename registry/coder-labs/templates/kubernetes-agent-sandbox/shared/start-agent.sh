#!/bin/sh
# Starts the Coder agent once the Pod's NetworkPolicy is in force. Used by
# main.tf (persistent homes) and cluster/main.tf (warm pools).
#
# VPC CNI can apply a new Pod's NetworkPolicy up to 30 s late, and can drop
# it when another Pod with the same name prefix is deleted. So the agent
# starts only once a TCP connection to the Kubernetes API server, which no
# profile allows, fails. If it still connects after about 60 s, the script
# exits and Kubernetes restarts the container. After start, the same check
# runs every 5 s, and the container stops if the API server becomes
# reachable. A slow TLS reply still counts as reachable, and so does a
# check that prints nothing.
api="https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT/"
api_open() {
  r=$(curl -sk -o /dev/null --noproxy '*' --connect-timeout 0.3 -m 1 -w '%{http_code} %{time_connect}' "$api" 2> /dev/null)
  [ -z "$r" ] && return 0
  awk -v t="${r#* }" 'BEGIN { exit !(t + 0 > 0) }'
}
i=0
while api_open; do
  i=$((i + 1))
  if [ "$i" -ge 240 ]; then
    echo "NetworkPolicy is not enforced" >&2
    exit 1
  fi
  sleep 0.25
done
echo "NetworkPolicy is in force after $i checks" >&2
# The agent must be PID 1, or the web terminal gets no input under Kata.
# So the re-check runs in the background.
(
  while sleep 5; do
    if api_open; then
      echo "NetworkPolicy is no longer enforced" >&2
      kill -TERM 1
      sleep 2
      kill -KILL -1
      exit 1
    fi
  done
) &
exec /usr/local/bin/coder agent
