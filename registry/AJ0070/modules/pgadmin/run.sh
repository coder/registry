#!/usr/bin/env sh

PORT=${PORT}
LOG_PATH=${LOG_PATH}

BOLD='\033[0;1m'

printf "$${BOLD}Installing pgAdmin!\n"

if ! command -v pip > /dev/null 2>&1; then
    echo "pip is not installed"
    echo "Please install pip in your Dockerfile/VM image before using this module"
    exit 1
fi

if ! command -v pgadmin4 > /dev/null 2>&1; then
  pip install pgadmin4-web
  echo "pgAdmin has been installed\n\n"
else
  echo "pgAdmin is already installed\n\n"
fi

echo "Starting pgAdmin in background..."
echo "check logs at $${LOG_PATH}"
pgadmin4 > $${LOG_PATH} 2>&1 &