#!/bin/bash
# boundary.sh - Boundary installation and setup for agentapi module.
# Sourced by main.sh when ENABLE_BOUNDARY=true.
# Exports AGENTAPI_BOUNDARY_PREFIX for use by module start scripts.

# Install boundary binary if needed.
# Uses one of three strategies:
#   1. Compile from source (compile_boundary_from_source=true)
#   2. Install from release (use_boundary_directly=true)
#   3. Use coder boundary subcommand (default, no installation needed)
install_boundary() {
  if [ "${COMPILE_BOUNDARY_FROM_SOURCE}" = "true" ]; then
    echo "Compiling boundary from source (version: ${BOUNDARY_VERSION})"

    # Remove existing boundary directory to allow re-running safely
    if [ -d boundary ]; then
      rm -rf boundary
    fi

    echo "Cloning boundary repository"
    git clone https://github.com/coder/boundary.git
    cd boundary
    git checkout "${BOUNDARY_VERSION}"

    make build

    sudo cp boundary /usr/local/bin/
    sudo chmod +x /usr/local/bin/boundary
    cd -
  elif [ "${USE_BOUNDARY_DIRECTLY}" = "true" ]; then
    echo "Installing boundary using official install script (version: ${BOUNDARY_VERSION})"
    curl -fsSL https://raw.githubusercontent.com/coder/boundary/main/install.sh | bash -s -- --version "${BOUNDARY_VERSION}"
  else
    echo "Using coder boundary subcommand (provided by Coder)"
  fi
}

# Set up boundary: install, write config, create wrapper script.
# Exports AGENTAPI_BOUNDARY_PREFIX pointing to the wrapper script.
setup_boundary() {
  local module_path="$1"

  echo "Setting up coder boundary..."

  # Install boundary binary if needed
  install_boundary

  # Determine which boundary command to use and create wrapper script
  BOUNDARY_WRAPPER_SCRIPT="$module_path/boundary-wrapper.sh"

  if [ "${COMPILE_BOUNDARY_FROM_SOURCE}" = "true" ] || [ "${USE_BOUNDARY_DIRECTLY}" = "true" ]; then
    # Use boundary binary directly (from compilation or release installation)
    cat > "${BOUNDARY_WRAPPER_SCRIPT}" << 'WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail
exec boundary -- "$@"
WRAPPER_EOF
  else
    # Use coder boundary subcommand (default)
    # Copy coder binary to strip CAP_NET_ADMIN capabilities.
    # This is necessary because boundary doesn't work with privileged binaries
    # (you can't launch privileged binaries inside network namespaces unless
    # you have sys_admin).
    if command_exists coder; then
      CODER_NO_CAPS="$module_path/coder-no-caps"
      if ! cp "$(which coder)" "$CODER_NO_CAPS"; then
        echo "Error: Failed to copy coder binary to ${CODER_NO_CAPS}. Boundary cannot be enabled." >&2
        exit 1
      fi
      cat > "${BOUNDARY_WRAPPER_SCRIPT}" << 'WRAPPER_EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/coder-no-caps" boundary -- "$@"
WRAPPER_EOF
    else
      echo "Error: ENABLE_BOUNDARY=true, but 'coder' command not found. Boundary cannot be enabled." >&2
      exit 1
    fi
  fi

  chmod +x "${BOUNDARY_WRAPPER_SCRIPT}"
  export AGENTAPI_BOUNDARY_PREFIX="${BOUNDARY_WRAPPER_SCRIPT}"
  echo "Boundary wrapper configured: ${AGENTAPI_BOUNDARY_PREFIX}"
}
