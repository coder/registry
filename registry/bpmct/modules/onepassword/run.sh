#!/usr/bin/env bash

SERVICE_ACCOUNT_TOKEN="${SERVICE_ACCOUNT_TOKEN}"
ACCOUNT_ADDRESS="${ACCOUNT_ADDRESS}"
ACCOUNT_EMAIL="${ACCOUNT_EMAIL}"
ACCOUNT_SECRET_KEY="${ACCOUNT_SECRET_KEY}"
ACCOUNT_PASSWORD="${ACCOUNT_PASSWORD}"
INSTALL_DIR="${INSTALL_DIR}"
OP_CLI_VERSION="${OP_CLI_VERSION}"
INSTALL_VSCODE_EXTENSION="${INSTALL_VSCODE_EXTENSION}"
PRE_INSTALL_SCRIPT="${PRE_INSTALL_SCRIPT}"
POST_INSTALL_SCRIPT="${POST_INSTALL_SCRIPT}"

fetch() {
  if command -v curl > /dev/null 2>&1; then
    curl -sSL --fail "$1"
  elif command -v wget > /dev/null 2>&1; then
    wget -qO- "$1"
  else
    printf "curl or wget is not installed.\n" && return 1
  fi
}

fetch_to_file() {
  if command -v curl > /dev/null 2>&1; then
    curl -sSL --fail "$2" -o "$1"
  elif command -v wget > /dev/null 2>&1; then
    wget -O "$1" "$2"
  else
    printf "curl or wget is not installed.\n" && return 1
  fi
}

run_script() {
  local ENCODED="$1" LABEL="$2"
  if [ -n "$${ENCODED}" ]; then
    printf "Running %s script...\n" "$${LABEL}"
    SCRIPT_PATH=$(mktemp /tmp/op-"$${LABEL}"-XXXXXX.sh)
    printf '%s' "$${ENCODED}" | base64 -d > "$${SCRIPT_PATH}"
    chmod +x "$${SCRIPT_PATH}"
    # shellcheck disable=SC2288
    "$${SCRIPT_PATH}" || printf "WARNING: %s script failed.\n" "$${LABEL}"
    rm -f "$${SCRIPT_PATH}"
  fi
}

install() {
  ARCH=$(uname -m)
  if [ "$${ARCH}" = "x86_64" ]; then
    ARCH="amd64"
  elif [ "$${ARCH}" = "aarch64" ]; then
    ARCH="arm64"
  else
    printf "Unsupported architecture: %s\n" "$${ARCH}" && return 1
  fi

  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  if [ "$${OS}" != "linux" ] && [ "$${OS}" != "darwin" ]; then
    printf "Unsupported OS: %s\n" "$${OS}" && return 1
  fi

  if [ "$${OP_CLI_VERSION}" = "latest" ]; then
    OP_CLI_VERSION=$(fetch "https://app-updates.agilebits.com/check/1/0/CLI2/en/2.0.0/N" \
      | grep -oE '"version":"[^"]+"' | head -1 | cut -d'"' -f4) || true
    if [ -z "$${OP_CLI_VERSION}" ]; then
      printf "Failed to resolve latest version, falling back to 2.30.3.\n"
      OP_CLI_VERSION="2.30.3"
    fi
  fi

  printf "1Password CLI version: %s\n" "$${OP_CLI_VERSION}"

  if command -v op > /dev/null 2>&1; then
    CURRENT_VERSION=$(op --version 2> /dev/null || true)
    if [ "$${CURRENT_VERSION}" = "$${OP_CLI_VERSION}" ]; then
      printf "Already installed.\n"
      return 0
    fi
  fi

  DOWNLOAD_URL="https://cache.agilebits.com/dist/1P/op2/pkg/v$${OP_CLI_VERSION}/op_$${OS}_$${ARCH}_v$${OP_CLI_VERSION}.zip"

  TEMP_DIR=$(mktemp -d)
  cd "$${TEMP_DIR}" || return 1

  if ! fetch_to_file op.zip "$${DOWNLOAD_URL}"; then
    rm -rf "$${TEMP_DIR}" && return 1
  fi

  if command -v unzip > /dev/null 2>&1; then
    unzip -o op.zip -d . > /dev/null
  elif command -v busybox > /dev/null 2>&1; then
    busybox unzip op.zip -d .
  else
    printf "unzip is not installed.\n"
    rm -rf "$${TEMP_DIR}" && return 1
  fi

  chmod +x op

  if [ -n "$${INSTALL_DIR}" ] && [ -w "$${INSTALL_DIR}" ]; then
    mv op "$${INSTALL_DIR}/op"
  elif [ -n "$${INSTALL_DIR}" ] && sudo mv op "$${INSTALL_DIR}/op" 2> /dev/null; then
    true
  else
    mkdir -p ~/.local/bin && mv op ~/.local/bin/op
    INSTALL_DIR=~/.local/bin
  fi
  printf "Installed to %s.\n" "$${INSTALL_DIR}"

  rm -rf "$${TEMP_DIR}"
}

run_script "$${PRE_INSTALL_SCRIPT}" "pre-install"

if ! install; then
  printf "Failed to install 1Password CLI.\n"
  exit 1
fi

if [ -n "$${SERVICE_ACCOUNT_TOKEN}" ]; then
  printf "Service account token configured.\n"
elif [ -n "$${ACCOUNT_ADDRESS}" ] && [ -n "$${ACCOUNT_EMAIL}" ]; then
  ADD_ARGS="--address $${ACCOUNT_ADDRESS} --email $${ACCOUNT_EMAIL}"
  if [ -n "$${ACCOUNT_SECRET_KEY}" ]; then
    ADD_ARGS="$${ADD_ARGS} --secret-key $${ACCOUNT_SECRET_KEY}"
  fi

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
    if op account list 2> /dev/null | grep -q "$${ACCOUNT_ADDRESS}"; then
      printf "Signed in to %s.\n" "$${ACCOUNT_ADDRESS}"
      if [ -n "$${OP_SESSION}" ]; then
        mkdir -p "$${HOME}/.op"
        SESSION_VAR="OP_SESSION_$(printf '%s' "$${ACCOUNT_ADDRESS}" | tr '.' '_' | tr '-' '_')"
        printf 'export %s="%s"\n' "$${SESSION_VAR}" "$${OP_SESSION}" > "$${HOME}/.op/session"
        chmod 600 "$${HOME}/.op/session"
        for rc in "$${HOME}/.bashrc" "$${HOME}/.zshrc"; do
          if [ -f "$${rc}" ] && ! grep -q ".op/session" "$${rc}" 2> /dev/null; then
            printf '\n[ -f ~/.op/session ] && . ~/.op/session\n' >> "$${rc}"
          fi
        done
      fi
    else
      printf "Sign-in failed. Run manually: op signin --account %s\n" "$${ACCOUNT_ADDRESS}"
    fi
  else
    printf "To sign in, run in your terminal:\n"
    printf "  op account add %s\n" "$${ADD_ARGS}"
  fi
fi

if [ "$${INSTALL_VSCODE_EXTENSION}" = "true" ]; then
  EXTENSION_ID="1Password.op-vscode"
  for _ in 1 2 3 4 5 6; do
    command -v code-server > /dev/null 2>&1 || command -v code > /dev/null 2>&1 && break
    sleep 5
  done
  if command -v code-server > /dev/null 2>&1; then
    cd /tmp && code-server --install-extension "$${EXTENSION_ID}" --force 2>&1 || true
  fi
  if command -v code > /dev/null 2>&1; then
    cd /tmp && code --install-extension "$${EXTENSION_ID}" --force 2>&1 || true
  fi
fi

run_script "$${POST_INSTALL_SCRIPT}" "post-install"
