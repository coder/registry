#!/usr/bin/env bash

# Convert all templated variables to shell variables.
SERVICE_ACCOUNT_TOKEN="${SERVICE_ACCOUNT_TOKEN}"
ACCOUNT_ADDRESS="${ACCOUNT_ADDRESS}"
ACCOUNT_EMAIL="${ACCOUNT_EMAIL}"
ACCOUNT_SECRET_KEY="${ACCOUNT_SECRET_KEY}"
ACCOUNT_PASSWORD="${ACCOUNT_PASSWORD}"
INSTALL_DIR="${INSTALL_DIR}"
OP_CLI_VERSION="${OP_CLI_VERSION}"
INSTALL_VSCODE_EXTENSION="${INSTALL_VSCODE_EXTENSION}"
POST_INSTALL_SCRIPT="${POST_INSTALL_SCRIPT}"

fetch() {
  url="$1"
  if command -v curl > /dev/null 2>&1; then
    curl -sSL --fail "$${url}"
  elif command -v wget > /dev/null 2>&1; then
    wget -qO- "$${url}"
  else
    printf "curl or wget is not installed.\n"
    return 1
  fi
}

fetch_to_file() {
  dest="$1"
  url="$2"
  if command -v curl > /dev/null 2>&1; then
    curl -sSL --fail "$${url}" -o "$${dest}"
  elif command -v wget > /dev/null 2>&1; then
    wget -O "$${dest}" "$${url}"
  else
    printf "curl or wget is not installed.\n"
    return 1
  fi
}

install() {
  ARCH=$(uname -m)
  if [ "$${ARCH}" = "x86_64" ]; then
    ARCH="amd64"
  elif [ "$${ARCH}" = "aarch64" ]; then
    ARCH="arm64"
  else
    printf "Unsupported architecture: %s\n" "$${ARCH}"
    return 1
  fi

  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  if [ "$${OS}" != "linux" ] && [ "$${OS}" != "darwin" ]; then
    printf "Unsupported OS: %s\n" "$${OS}"
    return 1
  fi

  # Resolve version.
  if [ "$${OP_CLI_VERSION}" = "latest" ]; then
    OP_CLI_VERSION=$(fetch "https://app-updates.agilebits.com/check/1/0/CLI2/en/2.0.0/N" |
      grep -oE '"version":"[^"]+"' | head -1 | cut -d'"' -f4) || true
    if [ -z "$${OP_CLI_VERSION}" ]; then
      printf "Failed to determine latest 1Password CLI version. Falling back to 2.30.3.\n"
      OP_CLI_VERSION="2.30.3"
    fi
  fi

  printf "1Password CLI version: %s\n" "$${OP_CLI_VERSION}"

  # Check if already installed at the right version.
  if command -v op > /dev/null 2>&1; then
    CURRENT_VERSION=$(op --version 2>/dev/null || true)
    if [ "$${CURRENT_VERSION}" = "$${OP_CLI_VERSION}" ]; then
      printf "1Password CLI %s is already installed.\n" "$${CURRENT_VERSION}"
      return 0
    fi
  fi

  # Build download URL.
  # https://developer.1password.com/docs/cli/get-started/#install
  DOWNLOAD_URL="https://cache.agilebits.com/dist/1P/op2/pkg/v$${OP_CLI_VERSION}/op_$${OS}_$${ARCH}_v$${OP_CLI_VERSION}.zip"
  printf "Downloading from %s\n" "$${DOWNLOAD_URL}"

  TEMP_DIR=$(mktemp -d)
  cd "$${TEMP_DIR}" || return 1

  if ! fetch_to_file op.zip "$${DOWNLOAD_URL}"; then
    printf "Failed to download 1Password CLI.\n"
    rm -rf "$${TEMP_DIR}"
    return 1
  fi

  if command -v unzip > /dev/null 2>&1; then
    unzip -o op.zip -d . > /dev/null
  elif command -v busybox > /dev/null 2>&1; then
    busybox unzip op.zip -d .
  else
    printf "unzip is not installed.\n"
    rm -rf "$${TEMP_DIR}"
    return 1
  fi

  chmod +x op

  if [ -n "$${INSTALL_DIR}" ] && [ -w "$${INSTALL_DIR}" ]; then
    mv op "$${INSTALL_DIR}/op"
    printf "1Password CLI installed to %s.\n" "$${INSTALL_DIR}"
  elif [ -n "$${INSTALL_DIR}" ] && sudo mv op "$${INSTALL_DIR}/op" 2>/dev/null; then
    printf "1Password CLI installed to %s.\n" "$${INSTALL_DIR}"
  else
    mkdir -p ~/.local/bin
    mv op ~/.local/bin/op
    printf "1Password CLI installed to ~/.local/bin. Add it to your PATH.\n"
  fi

  rm -rf "$${TEMP_DIR}"
  return 0
}

if ! install; then
  printf "Failed to install 1Password CLI.\n"
  exit 1
fi

# --- Authentication ---

if [ -n "$${SERVICE_ACCOUNT_TOKEN}" ]; then
  printf "1Password service account token configured via OP_SERVICE_ACCOUNT_TOKEN.\n"
elif [ -n "$${ACCOUNT_ADDRESS}" ] && [ -n "$${ACCOUNT_EMAIL}" ]; then
  # Pre-register the account so the user only needs to run 'op signin'.
  # The op CLI requires a tty for password input, so we cannot sign in
  # non-interactively here. We register the account details so the user
  # can sign in with a single command in their terminal.
  ADD_ARGS="--address $${ACCOUNT_ADDRESS} --email $${ACCOUNT_EMAIL}"
  if [ -n "$${ACCOUNT_SECRET_KEY}" ]; then
    ADD_ARGS="$${ADD_ARGS} --secret-key $${ACCOUNT_SECRET_KEY}"
  fi

  # Use expect to feed the password non-interactively if available
  # and a password was provided.
  if [ -n "$${ACCOUNT_PASSWORD}" ] && command -v expect > /dev/null 2>&1; then
    OP_SESSION=$(expect -c "
      log_user 0
      spawn op account add $${ADD_ARGS} --raw
      expect \"Enter the password*\"
      send \"$${ACCOUNT_PASSWORD}\r\"
      expect eof
      catch wait result
      set output \$expect_out(buffer)
      puts -nonewline \$output
    " 2>&1)
    if op account list 2>/dev/null | grep -q "$${ACCOUNT_ADDRESS}"; then
      printf "Account %s registered and signed in.\n" "$${ACCOUNT_ADDRESS}"
      if [ -n "$${OP_SESSION}" ]; then
        SESSION_FILE="$${HOME}/.op/session"
        mkdir -p "$${HOME}/.op"
        SESSION_VAR="OP_SESSION_$(printf '%s' "$${ACCOUNT_ADDRESS}" | tr '.' '_' | tr '-' '_')"
        printf 'export %s="%s"\n' "$${SESSION_VAR}" "$${OP_SESSION}" > "$${SESSION_FILE}"
        chmod 600 "$${SESSION_FILE}"
        for rc in "$${HOME}/.bashrc" "$${HOME}/.zshrc"; do
          if [ -f "$${rc}" ] && ! grep -q ".op/session" "$${rc}" 2>/dev/null; then
            printf '\n# 1Password CLI session\n[ -f ~/.op/session ] && . ~/.op/session\n' >> "$${rc}"
          fi
        done
        printf "Session token written to ~/.op/session.\n"
      fi
    else
      printf "WARNING: Failed to register account. Sign in manually: op signin --account %s\n" "$${ACCOUNT_ADDRESS}"
    fi
  else
    printf "Run the following in your terminal to sign in:\n"
    printf "  op account add %s\n" "$${ADD_ARGS}"
  fi
else
  printf "No credentials provided. Use 'op signin' to authenticate.\n"
fi

# --- VS Code Extension ---

if [ "$${INSTALL_VSCODE_EXTENSION}" = "true" ]; then
  EXTENSION_ID="1Password.op-vscode"

  # Wait briefly for code-server to be installed by a parallel
  # coder_script (e.g. the code-server module).
  for i in 1 2 3 4 5 6; do
    if command -v code-server > /dev/null 2>&1 || command -v code > /dev/null 2>&1; then
      break
    fi
    printf "Waiting for code-server/VS Code to be available...\n"
    sleep 5
  done

  # Install for code-server if available.
  if command -v code-server > /dev/null 2>&1; then
    printf "Installing %s for code-server...\n" "$${EXTENSION_ID}"
    cd /tmp && code-server --install-extension "$${EXTENSION_ID}" --force 2>&1 || true
  fi

  # Install for VS Code CLI if available.
  if command -v code > /dev/null 2>&1; then
    printf "Installing %s for VS Code...\n" "$${EXTENSION_ID}"
    cd /tmp && code --install-extension "$${EXTENSION_ID}" --force 2>&1 || true
  fi
fi

# --- Post-Install Script ---

if [ -n "$${POST_INSTALL_SCRIPT}" ]; then
  printf "Running post-install script...\n"
  SCRIPT_PATH=$(mktemp /tmp/op-post-install-XXXXXX.sh)
  printf '%s' "$${POST_INSTALL_SCRIPT}" | base64 -d > "$${SCRIPT_PATH}"
  chmod +x "$${SCRIPT_PATH}"
  if ! "$${SCRIPT_PATH}"; then
    printf "WARNING: Post-install script failed.\n"
  fi
  rm -f "$${SCRIPT_PATH}"
fi
