#!/usr/bin/env sh
# shellcheck shell=sh

DEVCONTAINERS_CLI_VERSION=$(printf '%s' "${DEVCONTAINERS_CLI_VERSION_B64}" | base64 -d) || {
  echo "ERROR: Failed to decode devcontainers_cli_version." >&2
  exit 1
}

REGISTRY_URL=""
if [ -n "${REGISTRY_URL_B64}" ]; then
  REGISTRY_URL=$(printf '%s' "${REGISTRY_URL_B64}" | base64 -d) || {
    echo "ERROR: Failed to decode registry_url." >&2
    exit 1
  }
fi

PACKAGE_SPEC="@devcontainers/cli@$DEVCONTAINERS_CLI_VERSION"

# We want to cd into `$CODER_SCRIPT_DATA_DIR` as the current directory
# might contain a `package.json` with `packageManager` set to something
# other than the detected package manager. When this happens, it can
# cause the installation to fail.
cd "$CODER_SCRIPT_DATA_DIR" || exit 1

# If @devcontainers/cli is already installed, we can skip
if DEVCONTAINER_PATH=$(command -v devcontainer 2> /dev/null); then
  echo "🥳 @devcontainers/cli is already installed into $DEVCONTAINER_PATH!"
  exit 0
fi

# Check if docker is installed
if ! command -v docker > /dev/null 2>&1; then
  echo "WARNING: Docker was not found but is required to use @devcontainers/cli, please make sure it is available."
fi

# Determine the package manager to use: npm, pnpm, or yarn
if command -v yarn > /dev/null 2>&1; then
  PACKAGE_MANAGER="yarn"
elif command -v npm > /dev/null 2>&1; then
  PACKAGE_MANAGER="npm"
elif command -v pnpm > /dev/null 2>&1; then
  PACKAGE_MANAGER="pnpm"
else
  echo "ERROR: No supported package manager (npm, pnpm, yarn) is installed. Please install one first." 1>&2
  exit 1
fi

INSTALL_PREFIX=$(dirname "$CODER_SCRIPT_BIN_DIR")

install() {
  echo "Installing $PACKAGE_SPEC using $PACKAGE_MANAGER..."

  case "$PACKAGE_MANAGER" in
    npm)
      set -- install --global "$PACKAGE_SPEC" --prefix "$INSTALL_PREFIX"
      ;;
    pnpm)
      PNPM_HOME="$CODER_SCRIPT_BIN_DIR"
      export PNPM_HOME
      set -- add --global "$PACKAGE_SPEC"
      ;;
    yarn)
      set -- global add "$PACKAGE_SPEC" --prefix "$INSTALL_PREFIX"
      ;;
    *)
      echo "ERROR: Unsupported package manager: $PACKAGE_MANAGER" >&2
      return 1
      ;;
  esac

  if [ -n "$REGISTRY_URL" ]; then
    set -- "$@" --registry "$REGISTRY_URL"
  fi

  "$PACKAGE_MANAGER" "$@"
}

install
INSTALL_EXIT=$?
if [ "$INSTALL_EXIT" -ne 0 ]; then
  echo "Failed to install @devcontainers/cli" >&2
  exit "$INSTALL_EXIT"
fi

if ! DEVCONTAINER_PATH=$(command -v devcontainer 2> /dev/null); then
  echo "Installation completed but 'devcontainer' command not found in PATH" >&2
  exit 1
fi

echo "🥳 @devcontainers/cli has been installed into $DEVCONTAINER_PATH!"
exit 0
