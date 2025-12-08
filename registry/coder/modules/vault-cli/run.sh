#!/usr/bin/env bash

# Convert all templated variables to shell variables
VAULT_ADDR=${VAULT_ADDR}
VAULT_TOKEN=${VAULT_TOKEN}
INSTALL_DIR=${INSTALL_DIR}
VAULT_CLI_VERSION=${VAULT_CLI_VERSION}
ENTERPRISE=${ENTERPRISE}

# Fetch URL content. If dest is provided, write to file; otherwise output to stdout.
# Usage: fetch <url> [dest]
fetch() {
  url="$1"
  dest="$${2:-}"

  # Detect HTTP client on first run
  if [ -z "$${HTTP_CLIENT:-}" ]; then
    if command -v curl > /dev/null 2>&1; then
      HTTP_CLIENT="curl"
    elif command -v wget > /dev/null 2>&1; then
      HTTP_CLIENT="wget"
    elif command -v busybox > /dev/null 2>&1; then
      HTTP_CLIENT="busybox"
    else
      printf "curl, wget, or busybox is not installed. Please install curl or wget in your image.\n"
      return 1
    fi
  fi

  if [ -n "$${dest}" ]; then
    # shellcheck disable=SC2195
    case "$${HTTP_CLIENT}" in
      curl) curl -sSL --fail "$${url}" -o "$${dest}" ;;
      wget) wget -O "$${dest}" "$${url}" ;;
      busybox) busybox wget -O "$${dest}" "$${url}" ;;
    esac
  else
    # shellcheck disable=SC2195
    case "$${HTTP_CLIENT}" in
      curl) curl -sSL --fail "$${url}" ;;
      wget) wget -qO- "$${url}" ;;
      busybox) busybox wget -qO- "$${url}" ;;
    esac
  fi
}

unzip_safe() {
  if command -v unzip > /dev/null 2>&1; then
    command unzip "$@"
  elif command -v busybox > /dev/null 2>&1; then
    busybox unzip "$@"
  else
    printf "unzip or busybox is not installed. Please install unzip in your image.\n"
    return 1
  fi
}

install() {
  # Get the architecture of the system
  ARCH=$(uname -m)
  if [ "$${ARCH}" = "x86_64" ]; then
    ARCH="amd64"
  elif [ "$${ARCH}" = "aarch64" ]; then
    ARCH="arm64"
  else
    printf "Unsupported architecture: %s\n" "$${ARCH}"
    return 1
  fi

  # Determine OS and validate
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  if [ "$${OS}" != "linux" ] && [ "$${OS}" != "darwin" ]; then
    printf "Unsupported OS: %s. Only linux and darwin are supported.\n" "$${OS}"
    return 1
  fi

  # Fetch release information from HashiCorp API
  if [ "$${VAULT_CLI_VERSION}" = "latest" ]; then
    if [ "$${ENTERPRISE}" = "true" ]; then
      API_URL="https://api.releases.hashicorp.com/v1/releases/vault/latest?license_class=enterprise"
    else
      API_URL="https://api.releases.hashicorp.com/v1/releases/vault/latest"
    fi
  else
    # For specific version, append +ent suffix for enterprise
    if [ "$${ENTERPRISE}" = "true" ]; then
      API_URL="https://api.releases.hashicorp.com/v1/releases/vault/$${VAULT_CLI_VERSION}+ent"
    else
      API_URL="https://api.releases.hashicorp.com/v1/releases/vault/$${VAULT_CLI_VERSION}"
    fi
  fi

  API_RESPONSE=$(fetch "$${API_URL}")
  if [ -z "$${API_RESPONSE}" ]; then
    printf "Failed to fetch release information from HashiCorp API.\n"
    return 1
  fi

  # Parse version and download URL from API response
  if command -v jq > /dev/null 2>&1; then
    VAULT_CLI_VERSION=$(printf '%s' "$${API_RESPONSE}" | jq -r '.version')
    DOWNLOAD_URL=$(printf '%s' "$${API_RESPONSE}" | jq -r --arg os "$${OS}" --arg arch "$${ARCH}" '.builds[] | select(.os == $os and .arch == $arch) | .url')
  else
    VAULT_CLI_VERSION=$(printf '%s' "$${API_RESPONSE}" | sed -n 's/.*"version":"\([^"]*\)".*/\1/p')
    # Fallback: construct URL manually if jq not available
    DOWNLOAD_URL="https://releases.hashicorp.com/vault/$${VAULT_CLI_VERSION}/vault_$${VAULT_CLI_VERSION}_$${OS}_$${ARCH}.zip"
  fi

  if [ -z "$${VAULT_CLI_VERSION}" ]; then
    printf "Failed to determine Vault version.\n"
    return 1
  fi

  if [ -z "$${DOWNLOAD_URL}" ]; then
    printf "Failed to determine download URL for Vault %s (%s/%s).\n" "$${VAULT_CLI_VERSION}" "$${OS}" "$${ARCH}"
    return 1
  fi

  printf "Vault version: %s\n" "$${VAULT_CLI_VERSION}"

  # Check if the vault CLI is installed and has the correct version
  installation_needed=1
  if command -v vault > /dev/null 2>&1; then
    CURRENT_VERSION=$(vault version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    if [ "$${CURRENT_VERSION}" = "$${VAULT_CLI_VERSION}" ]; then
      printf "Vault version %s is already installed and up-to-date.\n\n" "$${CURRENT_VERSION}"
      installation_needed=0
    fi
  fi

  if [ "$${installation_needed}" = "1" ]; then
    # Download and install Vault
    if [ -z "$${CURRENT_VERSION}" ]; then
      printf "Installing Vault CLI ...\n\n"
    else
      printf "Upgrading Vault CLI from version %s to %s ...\n\n" "$${CURRENT_VERSION}" "$${VAULT_CLI_VERSION}"
    fi

    # Create temporary directory for download
    TEMP_DIR=$(mktemp -d)
    cd "$${TEMP_DIR}" || return 1

    printf "Downloading from %s\n" "$${DOWNLOAD_URL}"
    if ! fetch "$${DOWNLOAD_URL}" vault.zip; then
      printf "Failed to download Vault.\n"
      rm -rf "$${TEMP_DIR}"
      return 1
    fi
    if ! unzip_safe vault.zip; then
      printf "Failed to unzip Vault.\n"
      rm -rf "$${TEMP_DIR}"
      return 1
    fi

    # Install to the specified directory
    if [ -n "$${INSTALL_DIR}" ] && [ -w "$${INSTALL_DIR}" ]; then
      mv vault "$${INSTALL_DIR}/vault"
      printf "Vault installed to %s successfully!\n\n" "$${INSTALL_DIR}"
    elif [ -n "$${INSTALL_DIR}" ] && [ ! -w "$${INSTALL_DIR}" ]; then
      # Try with sudo if install dir specified but not writable
      if sudo mv vault "$${INSTALL_DIR}/vault" 2> /dev/null; then
        printf "Vault installed to %s successfully!\n\n" "$${INSTALL_DIR}"
      else
        printf "Warning: Cannot write to %s. " "$${INSTALL_DIR}"
        mkdir -p ~/.local/bin
        if mv vault ~/.local/bin/vault; then
          printf "Installed to ~/.local/bin instead.\n"
          printf "Please add ~/.local/bin to your PATH to use vault CLI.\n"
        else
          printf "Failed to install Vault.\n"
          rm -rf "$${TEMP_DIR}"
          return 1
        fi
      fi
    elif sudo mv vault /usr/local/bin/vault 2> /dev/null; then
      printf "Vault installed successfully!\n\n"
    else
      mkdir -p ~/.local/bin
      if ! mv vault ~/.local/bin/vault; then
        printf "Failed to move Vault to local bin.\n"
        rm -rf "$${TEMP_DIR}"
        return 1
      fi
      printf "Please add ~/.local/bin to your PATH to use vault CLI.\n"
    fi

    # Clean up temp directory
    rm -rf "$${TEMP_DIR}"
  fi
  return 0
}

# Run installation
if ! install; then
  printf "Failed to install Vault CLI.\n"
  exit 1
fi

# Indicate token configuration status
if [ -n "$${VAULT_TOKEN}" ]; then
  printf "Vault token has been configured via VAULT_TOKEN environment variable.\n"
else
  printf "No Vault token provided. Use 'vault login' or set VAULT_TOKEN to authenticate.\n"
fi
