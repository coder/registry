#!/usr/bin/env bash

BOLD='\033[0;1m'
CODE='\033[36;40;1m'
RESET='\033[0m'
SCRIPT="${PERSONALIZE_PATH}"
SCRIPT="$${SCRIPT/#\~/$${HOME}}"

# If the personalize script doesn't exist, educate
# the user how they can customize their environment!
if [ ! -f $SCRIPT ]; then
  printf "✨ $${BOLD}You don't have a personalize script!\n\n"
  printf "Run $${CODE}touch $${SCRIPT} && chmod +x $${SCRIPT}$${RESET} to create one.\n"
  printf "It will run every time your workspace starts. Use it to install personal packages!\n\n"
  exit 0
fi

# Check if the personalize script is executable, if not,
# try to make it executable and educate the user if it fails.
if [ ! -x $SCRIPT ]; then
  echo "🔐 Your personalize script isn't executable!"
  printf "Run $CODE\`chmod +x $SCRIPT\`$RESET to make it executable.\n"
  exit 0
fi

# Run the personalize script!
$SCRIPT
