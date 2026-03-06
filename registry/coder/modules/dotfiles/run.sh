#!/usr/bin/env bash

set -euo pipefail

DOTFILES_URI="${DOTFILES_URI}"
DOTFILES_USER="${DOTFILES_USER}"
DOTFILES_BRANCH="${DOTFILES_BRANCH}"

if [ -n "$${DOTFILES_URI// }" ]; then
  if [ -z "$DOTFILES_USER" ]; then
    DOTFILES_USER="$USER"
  fi

  if [ -n "$DOTFILES_BRANCH" ]; then
    echo "✨ Applying dotfiles for user $DOTFILES_USER from branch $DOTFILES_BRANCH"
  else
    echo "✨ Applying dotfiles for user $DOTFILES_USER"
  fi

  if [ "$DOTFILES_USER" = "$USER" ]; then
    if [ -n "$DOTFILES_BRANCH" ]; then
      coder dotfiles "$DOTFILES_URI" --branch "$DOTFILES_BRANCH" -y 2>&1 | tee ~/.dotfiles.log
    else
      coder dotfiles "$DOTFILES_URI" -y 2>&1 | tee ~/.dotfiles.log
    fi
  else
    # The `eval echo ~"$DOTFILES_USER"` part is used to dynamically get the home directory of the user, see https://superuser.com/a/484280
    # eval echo ~coder -> "/home/coder"
    # eval echo ~root  -> "/root"

    CODER_BIN=$(which coder)
    DOTFILES_USER_HOME=$(eval echo ~"$DOTFILES_USER")
    if [ -n "$DOTFILES_BRANCH" ]; then
      sudo -u "$DOTFILES_USER" sh -c "'$CODER_BIN' dotfiles '$DOTFILES_URI' --branch '$DOTFILES_BRANCH' -y 2>&1 | tee '$DOTFILES_USER_HOME'/.dotfiles.log"
    else
      sudo -u "$DOTFILES_USER" sh -c "'$CODER_BIN' dotfiles '$DOTFILES_URI' -y 2>&1 | tee '$DOTFILES_USER_HOME'/.dotfiles.log"
    fi
  fi
fi
