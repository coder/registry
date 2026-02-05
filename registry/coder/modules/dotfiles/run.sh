#!/usr/bin/env bash

set -euo pipefail

DOTFILES_URI="${DOTFILES_URI}"
DOTFILES_USER="${DOTFILES_USER}"

# shellcheck disable=SC2157
if [ -n "$${DOTFILES_URI// }" ]; then
  if [ -z "$DOTFILES_USER" ]; then
    DOTFILES_USER="$USER"
  fi

  echo "✨ Applying dotfiles for user $DOTFILES_USER"

  if [ "$DOTFILES_USER" = "$USER" ]; then
    coder dotfiles "$DOTFILES_URI" -y 2>&1 | tee ~/.dotfiles.log
  else
    # The `eval echo ~"$DOTFILES_USER"` part is used to dynamically get the home directory of the user, see https://superuser.com/a/484280
    # eval echo ~coder -> "/home/coder"
    # eval echo ~root  -> "/root"

    CODER_BIN=$(which coder)
    DOTFILES_USER_HOME=$(eval echo ~"$DOTFILES_USER")
    sudo -u "$DOTFILES_USER" sh -c "'$CODER_BIN' dotfiles '$DOTFILES_URI' -y 2>&1 | tee '$DOTFILES_USER_HOME'/.dotfiles.log"
  fi
fi

POST_CLONE_SCRIPT="${POST_CLONE_SCRIPT}"

if [ -n "$POST_CLONE_SCRIPT" ]; then
  echo "Running post-clone script..."
  POST_CLONE_TMP=$(mktemp)
  echo "$POST_CLONE_SCRIPT" | base64 -d > "$POST_CLONE_TMP"
  chmod +x "$POST_CLONE_TMP"
  $POST_CLONE_TMP
  rm "$POST_CLONE_TMP"
fi
