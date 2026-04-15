#!/bin/bash
# Exports AGENTAPI_BOUNDARY_PREFIX for use by module start scripts.

set -o nounset
BOUNDARY_VERSION="${ARG_BOUNDARY_VERSION:-latest}"
COMPILE_BOUNDARY_FROM_SOURCE="${ARG_COMPILE_BOUNDARY_FROM_SOURCE:-false}"
USE_BOUNDARY_DIRECTLY="${ARG_USE_BOUNDARY_DIRECTLY:-false}"
MODULE_DIR="${ARG_MODULE_DIR:-}"
BOUNDARY_WRAPPER_PATH="${ARG_BOUNDARY_WRAPPER_PATH:-}"
set +o nounset

validate_boundary_subcommand() {
  if command -v coder > /dev/null 2>&1; then
    if coder boundary --help > /dev/null 2>&1; then
      return 0
    else
      echo "Error: 'coder' command found but does not support 'boundary' subcommand. Set use_boundary_directly=true or compile_boundary_from_source=true." >&2
      exit 1
    fi
  else
    echo "Error: 'coder' command not found. boundary cannot be enabled." >&2
    exit 1
  fi
}

# Install boundary binary if needed.
# Uses one of three strategies:
#   1. Compile from source (compile_boundary_from_source=true)
#   2. Install from release (use_boundary_directly=true)
#   3. Use coder boundary subcommand (default, no installation needed)
install_boundary() {
  if [[ "${COMPILE_BOUNDARY_FROM_SOURCE}" = "true" ]]; then
    echo "Compiling boundary from source (version: ${BOUNDARY_VERSION})"

    # Remove existing boundary directory to allow re-running safely
    if [[ -d boundary ]]; then
      rm -rf boundary
    fi

    echo "Cloning boundary repository"
    git clone https://github.com/coder/boundary.git
    cd boundary || exit 1
    git checkout "${BOUNDARY_VERSION}"

    make build

    sudo cp boundary /usr/local/bin/
    sudo chmod +x /usr/local/bin/boundary
    cd - || exit 1
  elif [[ "${USE_BOUNDARY_DIRECTLY}" = "true" ]]; then
    echo "Installing boundary using official install script (version: ${BOUNDARY_VERSION})"
    curl -fsSL https://raw.githubusercontent.com/coder/boundary/main/install.sh | bash -s -- --version "${BOUNDARY_VERSION}"
  else
    validate_boundary_subcommand
    echo "Using coder boundary subcommand (provided by Coder)"
  fi
}

# Set up boundary: install, write config, create wrapper script.
# Exports AGENTAPI_BOUNDARY_PREFIX pointing to the wrapper script.
setup_boundary() {
  local module_path="${MODULE_DIR}"
  local wrapper_path="${BOUNDARY_WRAPPER_PATH}"

  echo "Setting up coder boundary..."

  # Install boundary binary if needed
  install_boundary

  # Determine which boundary command to use and create wrapper script
  BOUNDARY_WRAPPER_SCRIPT="${wrapper_path}"

  if [[ "${COMPILE_BOUNDARY_FROM_SOURCE}" = "true" ]] || [[ "${USE_BOUNDARY_DIRECTLY}" = "true" ]]; then
    # Use boundary binary directly (from compilation or release installation)
    cat > "${BOUNDARY_WRAPPER_SCRIPT}" << 'WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail
exec boundary "$@"
WRAPPER_EOF
  else
    # Use coder boundary subcommand (default)
    # Copy coder binary to strip CAP_NET_ADMIN capabilities.
    # This is necessary because boundary doesn't work with privileged binaries
    # (you can't launch privileged binaries inside network namespaces unless
    # you have sys_admin).
    CODER_NO_CAPS="${module_path}/coder-no-caps"
    if ! cp "$(command -v coder)" "${CODER_NO_CAPS}"; then
      echo "Error: Failed to copy coder binary to ${CODER_NO_CAPS}. boundary cannot be enabled." >&2
      exit 1
    fi
    cat > "${BOUNDARY_WRAPPER_SCRIPT}" << 'WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/coder-no-caps" boundary "$@"
WRAPPER_EOF
  fi

  chmod +x "${BOUNDARY_WRAPPER_SCRIPT}"
  export AGENTAPI_BOUNDARY_PREFIX="${BOUNDARY_WRAPPER_SCRIPT}"
  echo "boundary wrapper configured: ${AGENTAPI_BOUNDARY_PREFIX}"
}

setup_boundary
