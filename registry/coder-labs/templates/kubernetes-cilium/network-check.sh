#!/usr/bin/env bash
# Tries a few connections from the workspace and prints which ones the
# CiliumNetworkPolicies allow. main.tf runs it as the Network check app.

check() {
  label=$1
  shift
  if "$@" > /dev/null 2>&1; then
    printf '  allowed  %s\n' "${label}"
  else
    printf '  blocked  %s\n' "${label}"
  fi
}

host=$(printf '%s' "${CODER_AGENT_URL}" | sed -E 's#^[a-z]+://([^/:]+).*#\1#')

echo "DNS: Cilium answers only allowed names."
for name in "${host}" github.com registry.npmjs.org example.com; do
  check "resolve ${name}" getent hosts "${name}"
done

echo
echo "TCP: Cilium allows only addresses from allowed answers."
check "Coder ${CODER_AGENT_URL}" curl -sS -o /dev/null --connect-timeout 3 "${CODER_AGENT_URL}/healthz"
check "https://github.com" curl -sS -o /dev/null --connect-timeout 3 https://github.com
check "https://registry.npmjs.org" curl -sS -o /dev/null --connect-timeout 3 https://registry.npmjs.org
check "https://example.com" curl -sS -o /dev/null --connect-timeout 3 https://example.com
check "https://1.1.1.1 (an IP address, no name)" curl -sS -o /dev/null --connect-timeout 3 https://1.1.1.1
check "cloud metadata 169.254.169.254" curl -sS -o /dev/null --connect-timeout 3 http://169.254.169.254/
if [[ -n "${KUBERNETES_SERVICE_HOST}" ]]; then
  check "Kubernetes API ${KUBERNETES_SERVICE_HOST}" curl -sk -o /dev/null --connect-timeout 3 "https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT:-443}/"
fi

echo
echo "Press Enter to close."
read -r _
