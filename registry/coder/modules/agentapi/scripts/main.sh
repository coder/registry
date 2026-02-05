#!/bin/bash
set -e
set -x

set -o nounset
MODULE_DIR_NAME="$ARG_MODULE_DIR_NAME"
WORKDIR="$ARG_WORKDIR"
INSTALL_AGENTAPI="$ARG_INSTALL_AGENTAPI"
AGENTAPI_VERSION="$ARG_AGENTAPI_VERSION"
WAIT_FOR_START_SCRIPT="$ARG_WAIT_FOR_START_SCRIPT"
AGENTAPI_PORT="$ARG_AGENTAPI_PORT"
AGENTAPI_SERVER_TYPE="$ARG_AGENTAPI_SERVER_TYPE"
AGENTAPI_TERM_WIDTH="$ARG_AGENTAPI_TERM_WIDTH"
AGENTAPI_TERM_HEIGHT="$ARG_AGENTAPI_TERM_HEIGHT"
AGENTAPI_INITIAL_PROMPT="${ARG_AGENTAPI_INITIAL_PROMPT:-}"
AGENTAPI_CHAT_BASE_PATH="${ARG_AGENTAPI_CHAT_BASE_PATH:-}"
TASK_ID="${ARG_TASK_ID:-}"
TASK_LOG_SNAPSHOT="${ARG_TASK_LOG_SNAPSHOT:-true}"
set +o nounset

command_exists() {
  command -v "$1" > /dev/null 2>&1
}

module_path="$HOME/${MODULE_DIR_NAME}"
mkdir -p "$module_path/scripts"

# Check for jq dependency if task log snapshot is enabled.
if [[ $TASK_LOG_SNAPSHOT == true ]] && [[ -n $TASK_ID ]]; then
  if ! command_exists jq; then
    echo "Warning: jq is not installed. Task log snapshot requires jq to capture conversation history."
    echo "Install jq to enable log snapshot functionality when the workspace stops."
  fi
fi
if [ ! -d "${WORKDIR}" ]; then
  echo "Warning: The specified folder '${WORKDIR}' does not exist."
  echo "Creating the folder..."
  mkdir -p "${WORKDIR}"
  echo "Folder created successfully."
fi

# Install AgentAPI if enabled
if [ "${INSTALL_AGENTAPI}" = "true" ]; then
  echo "Installing AgentAPI..."
  arch=$(uname -m)
  if [ "$arch" = "x86_64" ]; then
    binary_name="agentapi-linux-amd64"
  elif [ "$arch" = "aarch64" ]; then
    binary_name="agentapi-linux-arm64"
  else
    echo "Error: Unsupported architecture: $arch"
    exit 1
  fi
  if [ "${AGENTAPI_VERSION}" = "latest" ]; then
    # for the latest release the download URL pattern is different than for tagged releases
    # https://docs.github.com/en/repositories/releasing-projects-on-github/linking-to-releases
    download_url="https://github.com/coder/agentapi/releases/latest/download/$binary_name"
  else
    download_url="https://github.com/coder/agentapi/releases/download/${AGENTAPI_VERSION}/$binary_name"
  fi
  curl \
    --retry 5 \
    --retry-delay 5 \
    --fail \
    --retry-all-errors \
    -L \
    -C - \
    -o agentapi \
    "$download_url"
  chmod +x agentapi
  sudo mv agentapi /usr/local/bin/agentapi
fi
if ! command_exists agentapi; then
  echo "Error: AgentAPI is not installed. Please enable install_agentapi or install it manually."
  exit 1
fi

echo -n "${WAIT_FOR_START_SCRIPT}" > "$module_path/scripts/agentapi-wait-for-start.sh"
chmod +x "$module_path/scripts/agentapi-wait-for-start.sh"

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

cd "${WORKDIR}"

export AGENTAPI_CHAT_BASE_PATH="${AGENTAPI_CHAT_BASE_PATH:-}"
# Disable host header check since AgentAPI is proxied by Coder (which does its own validation)
export AGENTAPI_ALLOWED_HOSTS="*"

# Build agentapi server command arguments
ARGS=(
  "server"
  "--type" "${AGENTAPI_SERVER_TYPE}"
  "--port" "${AGENTAPI_PORT}"
  "--term-width" "${AGENTAPI_TERM_WIDTH}"
  "--term-height" "${AGENTAPI_TERM_HEIGHT}"
)
if [ -n "${AGENTAPI_INITIAL_PROMPT}" ]; then
  ARGS+=("--initial-prompt" "${AGENTAPI_INITIAL_PROMPT}")
fi

# Start agentapi server with the agent-command.sh script
nohup agentapi "${ARGS[@]}" -- "$module_path/agent-command.sh" &>> "$module_path/agentapi-start.log" &

"$module_path/scripts/agentapi-wait-for-start.sh" "${AGENTAPI_PORT}"
