#!/usr/bin/env bash

if [ -z "$CERT_PATH" ]; then
  CERT_PATH="${CERT_PATH}"
fi

if [ -z "$ACCESS_URL" ]; then
  ACCESS_URL="${ACCESS_URL}"
fi

if [ -z "$SESSION_TOKEN" ]; then
  SESSION_TOKEN="${SESSION_TOKEN}"
fi

set -euo pipefail

# Signal startup coordination
if command -v coder > /dev/null 2>&1; then
  coder exp sync start "aibridge-proxy-setup" > /dev/null 2>&1 || true
fi

if [ -z "$ACCESS_URL" ]; then
  echo "Error: Coder access URL is not set."
  exit 1
fi

if [ -z "$SESSION_TOKEN" ]; then
  echo "Error: Coder session token is not set."
  exit 1
fi

if ! command -v curl > /dev/null; then
  echo "Error: curl is not installed."
  exit 1
fi

echo "--------------------------------"
echo "AI Bridge Proxy Setup"
printf "Certificate path: %s\n" "$CERT_PATH"
printf "Access URL: %s\n" "$ACCESS_URL"
echo "--------------------------------"

CERT_DIR=$(dirname "$CERT_PATH")
mkdir -p "$CERT_DIR"

CERT_URL="$ACCESS_URL/api/v2/aibridge/proxy/ca-cert.pem"
echo "Downloading AI Bridge Proxy CA certificate from $CERT_URL..."

# Download the certificate with a 5s connection timeout and 10s total timeout
# to avoid the script hanging indefinitely.
if ! HTTP_STATUS=$(curl -s -o "$CERT_PATH" -w "%%{http_code}" \
  --connect-timeout 5 \
  --max-time 10 \
  -H "Coder-Session-Token: $SESSION_TOKEN" \
  "$CERT_URL"); then
  echo "❌ AI Bridge Proxy setup failed: could not connect to $CERT_URL."
  echo "Ensure AI Bridge Proxy is enabled and reachable from the workspace."
  rm -f "$CERT_PATH"
  exit 1
fi

if [ "$HTTP_STATUS" -ne 200 ]; then
  echo "❌ AI Bridge Proxy setup failed: unexpected response (HTTP $HTTP_STATUS)."
  echo "Ensure AI Bridge Proxy is enabled and reachable from the workspace."
  rm -f "$CERT_PATH"
  exit 1
fi

if [ ! -s "$CERT_PATH" ]; then
  echo "❌ AI Bridge Proxy setup failed: downloaded certificate is empty."
  rm -f "$CERT_PATH"
  exit 1
fi

echo "AI Bridge Proxy CA certificate saved to $CERT_PATH"
echo "✅ AI Bridge Proxy setup complete."

# Signal successful completion to unblock dependent scripts.
# Only called on success, if the script fails, dependents remain blocked
# until timeout, preventing them from starting without a valid certificate.
if command -v coder > /dev/null 2>&1; then
  coder exp sync complete "aibridge-proxy-setup" > /dev/null 2>&1 || true
fi
