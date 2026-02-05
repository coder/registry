#!/usr/bin/env bash

set -euo pipefail

DOTFILES_URI="${DOTFILES_URI}"
DOTFILES_USER="${DOTFILES_USER}"

# Validate DOTFILES_URI to prevent command injection (defense in depth)
if [ -n "$DOTFILES_URI" ]; then
  # shellcheck disable=SC2250
  if [[ "$DOTFILES_URI" =~ [^a-zA-Z0-9._/:@-] ]]; then
    echo "ERROR: DOTFILES_URI contains invalid characters" >&2
    exit 1
  fi
  if ! [[ "$DOTFILES_URI" =~ ^(https?://|git@|git://) ]]; then
    echo "ERROR: DOTFILES_URI must be a valid repository URL (https://, http://, git@, or git://)" >&2
    exit 1
  fi
fi

# shellcheck disable=SC2157
if [ -n "$${DOTFILES_URI// }" ]; then
  if [ -z "$DOTFILES_USER" ]; then
    DOTFILES_USER="$USER"
  fi

  echo "✨ Applying dotfiles for user $DOTFILES_USER"

  if [ "$DOTFILES_USER" = "$USER" ]; then
    coder dotfiles "$DOTFILES_URI" -y 2>&1 | tee ~/.dotfiles.log
  else
    DOTFILES_USER_HOME=$(getent passwd "$DOTFILES_USER" | cut -d: -f6)
    if [ -z "$DOTFILES_USER_HOME" ]; then
      echo "ERROR: Could not determine home directory for user $DOTFILES_USER" >&2
      exit 1
    fi

    CODER_BIN=$(command -v coder)
    sudo -u "$DOTFILES_USER" "$CODER_BIN" dotfiles "$DOTFILES_URI" -y 2>&1 | tee "$DOTFILES_USER_HOME/.dotfiles.log"
  fi
fi
