#!/usr/bin/env bash

set -euo pipefail

BOLD='\033[[0;1m'

printf "$${BOLD}Installing ttyd ${VERSION}\n\n"

ARCH=$(uname -m)
case "$${ARCH}" in
  x86_64) BINARY="ttyd.x86_64" ;;
  aarch64) BINARY="ttyd.aarch64" ;;
  armv7l) BINARY="ttyd.armhf" ;;
  armv6l) BINARY="ttyd.arm" ;;
  *)
    echo "ERROR: Unsupported architecture: $${ARCH}" >&2
    exit 1
    ;;
esac

BIN_DIR="$${HOME}/.local/bin"
mkdir -p "$${BIN_DIR}"
export PATH="$${BIN_DIR}:$${PATH}"

if ! command -v ttyd &> /dev/null; then
  DOWNLOAD_URL="https://github.com/tsl0922/ttyd/releases/download/${VERSION}/$${BINARY}"
  printf "Downloading ttyd from $${DOWNLOAD_URL}\n"
  curl -fsSL "$${DOWNLOAD_URL}" -o "$${BIN_DIR}/ttyd"
  chmod +x "$${BIN_DIR}/ttyd"
fi

printf "🥳 Installation complete!\n\n"

if [ -z "${COMMAND}" ]; then
  printf "No command specified, skipping ttyd startup.\n"
  exit 0
fi

ARGS="-p ${PORT}"

if [ "${WRITABLE}" = "true" ]; then
  ARGS="$${ARGS} -W"
fi

if [ "${MAX_CLIENTS}" -gt 0 ] 2> /dev/null; then
  ARGS="$${ARGS} -m ${MAX_CLIENTS}"
fi

if [ -n "${BASE_PATH}" ]; then
  ARGS="$${ARGS} -b ${BASE_PATH}"
fi

if [ -n "${ADDITIONAL_ARGS}" ]; then
  ARGS="$${ARGS} ${ADDITIONAL_ARGS}"
fi

printf "👷 Starting ttyd in background...\n"
printf "🖥️  Running: ttyd $${ARGS} -- ${COMMAND}\n\n"

ttyd $${ARGS} -- ${COMMAND} >> ${LOG_PATH} 2>&1 &

printf "📝 Logs at ${LOG_PATH}\n"
