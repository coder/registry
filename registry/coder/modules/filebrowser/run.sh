#!/usr/bin/env bash

set -euo pipefail

BOLD='\033[[0;1m'

printf "$${BOLD}Installing filebrowser \n\n"

# Check if filebrowser is installed
if ! command -v filebrowser &> /dev/null; then
  curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash
fi

printf "🥳 Installation complete! \n\n"

printf "🛠️  Configuring filebrowser \n\n"

ROOT_DIR=${FOLDER}
ROOT_DIR=$${ROOT_DIR/\~/$HOME}

echo "DB_PATH: ${DB_PATH}"

export FB_DATABASE="${DB_PATH}"

if PID="$(pgrep -x filebrowser)"; then
  echo "File Browser is already running (PID: $${PID})"

  # Show which database the running process is using.
  RUNNING_DB="$(tr '\0' '\n' < /proc/$${PID}/environ | grep '^FB_DATABASE=' | cut -d= -f2- || true)"

  echo "Running database: $${RUNNING_DB}"

  if [[ "$${RUNNING_DB}" == "${DB_PATH}" ]]; then
    echo "Existing File Browser already uses ${DB_PATH}."
    echo "Skipping configuration and startup."

    exit 0
  fi

  echo "A File Browser process is already running but is using another database."
  echo "Continuing..."
fi

if [[ ! -f "${DB_PATH}" ]]; then
  echo "Initializing File Browser database..."

  filebrowser config init 2>&1 | tee -a "${LOG_PATH}"

  filebrowser users add \
    admin \
    "coderPASSWORD" \
    --perm.admin=true \
    --viewMode=mosaic \
    2>&1 | tee -a "${LOG_PATH}"
fi

filebrowser config set \
  --baseURL="${SERVER_BASE_PATH}" \
  --port="${PORT}" \
  --auth.method=noauth \
  --root="$${ROOT_DIR}" \
  2>&1 | tee -a "${LOG_PATH}"

printf "👷 Starting filebrowser in background... \n\n"

printf "📂 Serving $${ROOT_DIR} at http://localhost:${PORT} \n\n"

filebrowser >> ${LOG_PATH} 2>&1 &

printf "📝 Logs at ${LOG_PATH} \n\n"
