#!/usr/bin/env bash

BOLD='\033[0;1m'
CODE='\033[36;40;1m'
RESET='\033[0m'
# shellcheck disable=SC2016 # Terraform replaces this placeholder.
SCRIPT=$(printf '%s' '${PERSONALIZE_PATH}' | base64 -d) || {
  echo "Failed to decode the personalize script path." >&2
  exit 1
}
DISPLAY_PATH="$SCRIPT"
case "$SCRIPT" in
  \~) SCRIPT="$${HOME}" ;;
  \~/*) SCRIPT="$${HOME}/$${SCRIPT#??}" ;;
  *) ;;
esac

# If the personalize script doesn't exist, educate
# the user how they can customize their environment!
if [ ! -f "$SCRIPT" ]; then
  printf "✨ %bYou don't have a personalize script!\n\n" "$BOLD"
  printf 'Create a script at %b%s%b and make it executable.\n' "$CODE" "$DISPLAY_PATH" "$RESET"
  printf 'It will run every time your workspace starts. Use it to install personal packages!\n\n'
  exit 0
fi

# Check if the personalize script is executable, if not,
# try to make it executable and educate the user if it fails.
if [ ! -x "$SCRIPT" ]; then
  echo "🔐 Your personalize script isn't executable!"
  printf 'Make %b%s%b executable before restarting the workspace.\n' "$CODE" "$DISPLAY_PATH" "$RESET"
  exit 0
fi

# Run the personalize script!
"$SCRIPT"
