#!/usr/bin/env bash

set -euo pipefail

REPO_URL="${REPO_URL}"
CLONE_PATH="${CLONE_PATH}"
BRANCH_NAME="${BRANCH_NAME}"
# Expand home if it's specified!
CLONE_PATH="$${CLONE_PATH/#\~/$${HOME}}"
EXTRA_ARGS="${EXTRA_ARGS}"
POST_CLONE_SCRIPT="${POST_CLONE_SCRIPT}"
PRE_CLONE_SCRIPT="${PRE_CLONE_SCRIPT}"
SCRIPTS_DIR="${SCRIPTS_DIR}"
PRE_CLONE_LOG_PATH="${PRE_CLONE_LOG_PATH}"
POST_CLONE_LOG_PATH="${POST_CLONE_LOG_PATH}"

# Check if the variable is empty...
if [ -z "$REPO_URL" ]; then
  echo "No repository specified!"
  exit 1
fi

# Check if the variable is empty...
if [ -z "$CLONE_PATH" ]; then
  echo "No clone path specified!"
  exit 1
fi

# Check if `git` is installed...
if ! command -v git > /dev/null; then
  echo "Git is not installed!"
  exit 1
fi

# Check if the directory for the cloning exists
# and if not, create it
if [ ! -d "$CLONE_PATH" ]; then
  echo "Creating directory $CLONE_PATH..."
  mkdir -p "$CLONE_PATH"
fi

# Run pre-clone script if provided
if [ -n "$PRE_CLONE_SCRIPT" ]; then
  echo "Running pre-clone script..."
  PRE_CLONE_PATH="$SCRIPTS_DIR/pre_clone.sh"
  echo "$PRE_CLONE_SCRIPT" | base64 -d > "$PRE_CLONE_PATH"
  chmod +x "$PRE_CLONE_PATH"
  "$PRE_CLONE_PATH" 2>&1 | tee "$PRE_CLONE_LOG_PATH"
fi

# Build optional git clone flags
extra_args=()
if [ -n "$EXTRA_ARGS" ]; then
  while IFS= read -r arg || [ -n "$arg" ]; do
    [ -n "$arg" ] && extra_args+=("$arg")
  done < <(echo "$EXTRA_ARGS" | base64 -d)
fi

# For SSH URLs, populate known_hosts before cloning to prevent "Host key verification failed"
# on new workspaces where known_hosts is empty.
if echo "$REPO_URL" | grep -qE '^git@|^ssh://'; then
  SSH_HOST=$(echo "$REPO_URL" | sed -E 's|^(ssh://)?([^@/]+@)?([^:/]+).*|\3|')
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  touch "$HOME/.ssh/known_hosts"
  chmod 600 "$HOME/.ssh/known_hosts"
  if ! ssh-keygen -F "$SSH_HOST" > /dev/null 2>&1; then
    echo "Adding host key for $SSH_HOST to known_hosts..."
    if command -v ssh-keyscan > /dev/null 2>&1; then
      if KNOWN_HOST_ENTRY=$(ssh-keyscan -H -t rsa,ecdsa,ed25519 "$SSH_HOST" 2> /dev/null) && [ -n "$KNOWN_HOST_ENTRY" ]; then
        printf '%s\n' "$KNOWN_HOST_ENTRY" >> "$HOME/.ssh/known_hosts"
        echo "Host key for $SSH_HOST added to known_hosts."
      else
        echo "WARNING: ssh-keyscan failed for $SSH_HOST. Clone may fail if host key is not trusted."
      fi
    else
      echo "ssh-keyscan not available. Using StrictHostKeyChecking=accept-new."
      export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new"
    fi
  fi
fi

# Check if the directory is empty
# and if it is, clone the repo, otherwise skip cloning
if [ -z "$(ls -A "$CLONE_PATH")" ]; then
  if [ -z "$BRANCH_NAME" ]; then
    echo "Cloning $REPO_URL to $CLONE_PATH..."
    git clone $${extra_args[@]+"$${extra_args[@]}"} "$REPO_URL" "$CLONE_PATH"
  else
    echo "Cloning $REPO_URL to $CLONE_PATH on branch $BRANCH_NAME..."
    git clone $${extra_args[@]+"$${extra_args[@]}"} -b "$BRANCH_NAME" "$REPO_URL" "$CLONE_PATH"
  fi
else
  echo "$CLONE_PATH already exists and isn't empty, skipping clone!"
fi

# Run post-clone script if provided
if [ -n "$POST_CLONE_SCRIPT" ]; then
  echo "Running post-clone script..."
  POST_CLONE_PATH="$SCRIPTS_DIR/post_clone.sh"
  echo "$POST_CLONE_SCRIPT" | base64 -d > "$POST_CLONE_PATH"
  chmod +x "$POST_CLONE_PATH"
  cd "$CLONE_PATH" || exit
  "$POST_CLONE_PATH" 2>&1 | tee "$POST_CLONE_LOG_PATH"
fi
