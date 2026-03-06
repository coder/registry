#!/usr/bin/env bash

set -euo pipefail

BOLD='\033[[0;1m'

printf "%sInstalling ttyd %s\n\n" "$${BOLD}" "${VERSION}"

ARCH=$(uname -m)
# shellcheck disable=SC2195
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

TTYD_BIN="$${BIN_DIR}/ttyd"
LOCK_DIR="/tmp/ttyd-install.lock"

if [[ ! -f "$${TTYD_BIN}" ]]; then
  if mkdir "$${LOCK_DIR}" 2> /dev/null; then
    if [[ ! -f "$${TTYD_BIN}" ]]; then
      DOWNLOAD_URL="https://github.com/tsl0922/ttyd/releases/download/${VERSION}/$${BINARY}"
      printf "Downloading ttyd from %s\n" "$${DOWNLOAD_URL}"
      curl -fsSL "$${DOWNLOAD_URL}" -o "$${TTYD_BIN}"
      chmod +x "$${TTYD_BIN}"
    fi
    rmdir "$${LOCK_DIR}" 2> /dev/null || true
  else
    printf "Waiting for ttyd installation to complete...\n"
    while [[ -d "$${LOCK_DIR}" ]] && [[ ! -f "$${TTYD_BIN}" ]]; do
      sleep 0.5
    done
  fi
fi

printf "Installation complete!\n\n"

if [[ -z "${COMMAND}" ]]; then
  printf "No command specified, skipping ttyd startup.\n"
  exit 0
fi

ARGS="-p ${PORT}"

if [[ "${WRITABLE}" = "true" ]]; then
  ARGS="$${ARGS} -W"
fi

if [[ "${MAX_CLIENTS}" -gt 0 ]] 2> /dev/null; then
  ARGS="$${ARGS} -m ${MAX_CLIENTS}"
fi

if [[ -n "${BASE_PATH}" ]]; then
  ARGS="$${ARGS} -b ${BASE_PATH}"
fi

if [[ -n "${ADDITIONAL_ARGS}" ]]; then
  ARGS="$${ARGS} ${ADDITIONAL_ARGS}"
fi

TTYD_LOG_PATH="${LOG_PATH}"
TTYD_LOG_PATH="$${TTYD_LOG_PATH/#\~/$${HOME}}"
TTYD_LOG_DIR="$${TTYD_LOG_PATH%/*}"
mkdir -p "$${TTYD_LOG_DIR}"

printf "Starting ttyd in background...\n"
printf "Running: ttyd %s -- %s\n\n" "$${ARGS}" "${COMMAND}"

# shellcheck disable=SC2086
ttyd $${ARGS} -- ${COMMAND} >> "$${TTYD_LOG_PATH}" 2>&1 &

printf "Logs at %s\n" "$${TTYD_LOG_PATH}"
