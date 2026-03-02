#!/bin/bash
set -e
set -x

set -o nounset
MODULE_DIR_NAME="$ARG_MODULE_DIR_NAME"
WORKDIR="$ARG_WORKDIR"
PRE_INSTALL_SCRIPT="$ARG_PRE_INSTALL_SCRIPT"
INSTALL_SCRIPT="$ARG_INSTALL_SCRIPT"
INSTALL_AGENTAPI="$ARG_INSTALL_AGENTAPI"
AGENTAPI_VERSION="$ARG_AGENTAPI_VERSION"
START_SCRIPT="$ARG_START_SCRIPT"
WAIT_FOR_START_SCRIPT="$ARG_WAIT_FOR_START_SCRIPT"
POST_INSTALL_SCRIPT="$ARG_POST_INSTALL_SCRIPT"
AGENTAPI_PORT="$ARG_AGENTAPI_PORT"
AGENTAPI_CHAT_BASE_PATH="${ARG_AGENTAPI_CHAT_BASE_PATH:-}"
TASK_ID="${ARG_TASK_ID:-}"
TASK_LOG_SNAPSHOT="${ARG_TASK_LOG_SNAPSHOT:-true}"
ENABLE_BOUNDARY="${ARG_ENABLE_BOUNDARY:-false}"
BOUNDARY_JAIL_TYPE="${ARG_BOUNDARY_JAIL_TYPE:-nsjail}"
BOUNDARY_PROXY_PORT="${ARG_BOUNDARY_PROXY_PORT:-8087}"
BOUNDARY_CONFIG_PATH="${ARG_BOUNDARY_CONFIG_PATH:-}"
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
if [ -n "${PRE_INSTALL_SCRIPT}" ]; then
  echo "Running pre-install script..."
  echo -n "${PRE_INSTALL_SCRIPT}" > "$module_path/pre_install.sh"
  chmod +x "$module_path/pre_install.sh"
  "$module_path/pre_install.sh" 2>&1 | tee "$module_path/pre_install.log"
fi

echo "Running install script..."
echo -n "${INSTALL_SCRIPT}" > "$module_path/install.sh"
chmod +x "$module_path/install.sh"
"$module_path/install.sh" 2>&1 | tee "$module_path/install.log"

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

echo -n "${START_SCRIPT}" > "$module_path/scripts/agentapi-start.sh"
echo -n "${WAIT_FOR_START_SCRIPT}" > "$module_path/scripts/agentapi-wait-for-start.sh"
chmod +x "$module_path/scripts/agentapi-start.sh"
chmod +x "$module_path/scripts/agentapi-wait-for-start.sh"

if [ -n "${POST_INSTALL_SCRIPT}" ]; then
  echo "Running post-install script..."
  echo -n "${POST_INSTALL_SCRIPT}" > "$module_path/post_install.sh"
  chmod +x "$module_path/post_install.sh"
  "$module_path/post_install.sh" 2>&1 | tee "$module_path/post_install.log"
fi

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

cd "${WORKDIR}"

# Set up boundary if enabled
BOUNDARY_WRAPPER=""
if [ "${ENABLE_BOUNDARY}" = "true" ]; then
  echo "Setting up coder boundary..."

  # Create boundary config directory
  mkdir -p ~/.config/coder_boundary

  # Write boundary config if custom path not provided
  if [ -z "${BOUNDARY_CONFIG_PATH}" ]; then
    echo "Generating boundary config with jail_type=${BOUNDARY_JAIL_TYPE} and proxy_port=${BOUNDARY_PROXY_PORT}"
    cat > ~/.config/coder_boundary/config.yaml <<EOF
jail_type: ${BOUNDARY_JAIL_TYPE}
proxy_port: ${BOUNDARY_PROXY_PORT}
log_level: warn
EOF
  else
    echo "Using custom boundary config from ${BOUNDARY_CONFIG_PATH}"
    cp "${BOUNDARY_CONFIG_PATH}" ~/.config/coder_boundary/config.yaml
  fi

  chmod 600 ~/.config/coder_boundary/config.yaml

  # Copy coder binary to strip CAP_NET_ADMIN capabilities
  # This is necessary because boundary doesn't work with privileged binaries
  if command_exists coder; then
    CODER_NO_CAPS="$(dirname "$(which coder)")/coder-no-caps"
    cp "$(which coder)" "$CODER_NO_CAPS"
    BOUNDARY_WRAPPER="$CODER_NO_CAPS boundary --"
    echo "Boundary wrapper configured: ${BOUNDARY_WRAPPER}"
  else
    echo "Warning: coder command not found, boundary will not be enabled"
    BOUNDARY_WRAPPER=""
  fi
fi

export AGENTAPI_CHAT_BASE_PATH="${AGENTAPI_CHAT_BASE_PATH:-}"
# Disable host header check since AgentAPI is proxied by Coder (which does its own validation)
export AGENTAPI_ALLOWED_HOSTS="*"

# Start agentapi with or without boundary wrapper
if [ -n "${BOUNDARY_WRAPPER}" ]; then
  echo "Starting agentapi with boundary wrapper..."
  nohup ${BOUNDARY_WRAPPER} "$module_path/scripts/agentapi-start.sh" true "${AGENTAPI_PORT}" &> "$module_path/agentapi-start.log" &
else
  nohup "$module_path/scripts/agentapi-start.sh" true "${AGENTAPI_PORT}" &> "$module_path/agentapi-start.log" &
fi
"$module_path/scripts/agentapi-wait-for-start.sh" "${AGENTAPI_PORT}"
