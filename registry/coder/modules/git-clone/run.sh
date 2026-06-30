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
