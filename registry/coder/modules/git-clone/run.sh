#!/usr/bin/env sh

REPO_URL="${REPO_URL}"
CLONE_PATH="${CLONE_PATH}"
BRANCH_NAME="${BRANCH_NAME}"
# Expand home if it's specified!
CLONE_PATH="$${CLONE_PATH/#\~/$${HOME}}"
DEPTH="${DEPTH}"
POST_CLONE_SCRIPT="${POST_CLONE_SCRIPT}"
CLONE_ARGS="${CLONE_ARGS}"

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
  if [ -n "$BRANCH_NAME" ]; then
    echo "Cloning $REPO_URL to $CLONE_PATH on branch $BRANCH_NAME..."
  else
    echo "Cloning $REPO_URL to $CLONE_PATH..."
  fi

  # Build the git clone command arguments
  set --
  if [ -n "$DEPTH" ] && [ "$DEPTH" -gt 0 ]; then
    set -- "$@" --depth "$DEPTH"
  fi
  if [ -n "$BRANCH_NAME" ]; then
    set -- "$@" -b "$BRANCH_NAME"
  fi
  # shellcheck disable=SC2086
  if [ -n "$CLONE_ARGS" ]; then
    set -- "$@" $CLONE_ARGS
  fi
  set -- "$@" "$REPO_URL" "$CLONE_PATH"

  git clone "$@"
else
  echo "$CLONE_PATH already exists and isn't empty, skipping clone!"
fi

# Run post-clone script if provided
if [ -n "$POST_CLONE_SCRIPT" ]; then
  echo "Running post-clone script..."
  echo "$POST_CLONE_SCRIPT" | base64 -d > /tmp/post_clone.sh
  chmod +x /tmp/post_clone.sh
  cd "$CLONE_PATH" || exit
  /tmp/post_clone.sh
  rm /tmp/post_clone.sh
fi
