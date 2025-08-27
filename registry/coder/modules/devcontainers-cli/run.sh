#!/usr/bin/env sh

# We want to cd into `$CODER_SCRIPT_DATA_DIR` as the current directory
# might contain a `package.json` with `packageManager` set to something
# other than the detected package manager. When this happens, it can
# cause the installation to fail.
cd "$CODER_SCRIPT_DATA_DIR"

# If @devcontainers/cli is already installed, we can skip
if command -v devcontainer > /dev/null 2>&1; then
  echo "🥳 @devcontainers/cli is already installed into $(which devcontainer)!"
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

install() {
  echo "Installing @devcontainers/cli using $PACKAGE_MANAGER..."
  if [ "$PACKAGE_MANAGER" = "npm" ]; then
    npm install -g @devcontainers/cli
  elif [ "$PACKAGE_MANAGER" = "pnpm" ]; then
    # Check if PNPM_HOME is set, if not, set it to the script's bin directory
    # pnpm needs this to be set to install binaries
    # coder agent ensures this part is part of the PATH
    # so that the devcontainer command is available
    if [ -z "$PNPM_HOME" ]; then
      PNPM_HOME="$CODER_SCRIPT_BIN_DIR"
      export PNPM_HOME
    fi
    pnpm add -g @devcontainers/cli
  elif [ "$PACKAGE_MANAGER" = "yarn" ]; then
    yarn global add @devcontainers/cli --prefix "$(dirname "$CODER_SCRIPT_BIN_DIR")"
  fi
}

if ! install; then
  echo "Failed to install @devcontainers/cli" >&2
  exit 1
fi

if ! command -v devcontainer > /dev/null 2>&1; then
  echo "Installation completed but 'devcontainer' command not found in PATH" >&2
  exit 1
fi

echo "🥳 @devcontainers/cli has been installed into $(which devcontainer)!"
exit 0
