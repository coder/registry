#!/usr/bin/env bash

REPO_URL="${REPO_URL}"
CLONE_PATH="${CLONE_PATH}"
BRANCH_NAME="${BRANCH_NAME}"
# Expand home if it's specified!
CLONE_PATH="$${CLONE_PATH/#\~/$${HOME}}"

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

# Check if the directory is empty
# and if it is, clone the repo, otherwise skip cloning
if [ -z "$(ls -A "$CLONE_PATH")" ]; then
  if [ -z "$BRANCH_NAME" ]; then
    echo "Cloning $REPO_URL to $CLONE_PATH..."
    git clone "$REPO_URL" "$CLONE_PATH"
  else
    echo "Cloning $REPO_URL to $CLONE_PATH on branch $BRANCH_NAME..."
    git clone "$REPO_URL" -b "$BRANCH_NAME" "$CLONE_PATH"
  fi
else
  echo "$CLONE_PATH already exists and isn't empty, skipping clone!"
  exit 0
fi
