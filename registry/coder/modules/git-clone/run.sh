#!/usr/bin/env bash

set -euo pipefail

REPO_URL="${REPO_URL}"
CLONE_PATH="${CLONE_PATH}"
BRANCH_NAME="${BRANCH_NAME}"
# Expand home if it's specified!
CLONE_PATH="$${CLONE_PATH/#\~/$${HOME}}"
DEPTH="${DEPTH}"
RECURSE_SUBMODULES="${RECURSE_SUBMODULES}"
CLONE_JOBS="${CLONE_JOBS}"
POST_CLONE_SCRIPT="${POST_CLONE_SCRIPT}"
PRE_CLONE_SCRIPT="${PRE_CLONE_SCRIPT}"

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
  PRE_CLONE_TMP=$(mktemp)
  echo "$PRE_CLONE_SCRIPT" | base64 -d > "$PRE_CLONE_TMP"
  chmod +x "$PRE_CLONE_TMP"
  $PRE_CLONE_TMP
  rm "$PRE_CLONE_TMP"
fi

# Build optional git clone flags
CLONE_FLAGS=()
if [ "$DEPTH" -gt 0 ]; then
  CLONE_FLAGS+=(--depth "$DEPTH")
fi
if [ "$RECURSE_SUBMODULES" = "true" ]; then
  CLONE_FLAGS+=(--recurse-submodules)
fi
if [ "$CLONE_JOBS" -gt 0 ]; then
  CLONE_FLAGS+=(--jobs "$CLONE_JOBS")
fi

# Check if the directory is empty
# and if it is, clone the repo, otherwise skip cloning
if [ -z "$(ls -A "$CLONE_PATH")" ]; then
  if [ -z "$BRANCH_NAME" ]; then
    echo "Cloning $REPO_URL to $CLONE_PATH..."
    git clone "$${CLONE_FLAGS[@]}" "$REPO_URL" "$CLONE_PATH"
  else
    echo "Cloning $REPO_URL to $CLONE_PATH on branch $BRANCH_NAME..."
    git clone "$${CLONE_FLAGS[@]}" -b "$BRANCH_NAME" "$REPO_URL" "$CLONE_PATH"
  fi
else
  echo "$CLONE_PATH already exists and isn't empty, skipping clone!"
fi

# Run post-clone script if provided
if [ -n "$POST_CLONE_SCRIPT" ]; then
  echo "Running post-clone script..."
  POST_CLONE_TMP=$(mktemp)
  echo "$POST_CLONE_SCRIPT" | base64 -d > "$POST_CLONE_TMP"
  chmod +x "$POST_CLONE_TMP"
  cd "$CLONE_PATH" || exit
  $POST_CLONE_TMP
  rm "$POST_CLONE_TMP"
fi
