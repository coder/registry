#!/usr/bin/env bash

BOLD='\033[0;1m'
CODE='\033[36;40;1m'
RESET='\033[0m'

# shellcheck disable=SC2016 # Terraform replaces this placeholder.
PERSONALIZE_SCRIPT=$(printf '%s' '${PERSONALIZE_PATH}' | base64 -d) || {
  echo "Failed to decode the personalize script path." >&2
  exit 1
}
DISPLAY_PATH="$PERSONALIZE_SCRIPT"

case "$PERSONALIZE_SCRIPT" in
  \~) PERSONALIZE_SCRIPT="$${HOME}" ;;
  \~/*) PERSONALIZE_SCRIPT="$${HOME}/$${PERSONALIZE_SCRIPT#??}" ;;
esac
case "$PERSONALIZE_SCRIPT" in
  /*) ;;
  *) PERSONALIZE_SCRIPT="$${PWD%/}/$PERSONALIZE_SCRIPT" ;;
esac

DROP_IN_DIR="$PERSONALIZE_SCRIPT.d"
MODULE_DIR="$HOME/.coder-modules/coder/personalize"
CONFIG_FILE="$MODULE_DIR/config"

# Prints NAME='VALUE' with each ' in VALUE written as '\''. sed runs with
# LC_ALL=C because in a UTF-8 locale busybox sed does not match a quote that
# follows an invalid byte.
write_value() {
  printf "%s='" "$1" || return
  printf '%s' "$2" | LC_ALL=C sed "s/'/'\\\\''/g" || return
  printf "'\n"
}

# Writes the config file to a temporary file in the same directory and renames
# it, so that readers see either the previous file or the complete new one.
# Runs in a subshell so that the EXIT trap removes the temporary file when a
# step fails.
write_config() (
  mkdir -p "$MODULE_DIR" || exit 1

  # mv would move the temporary file into a directory at the config path.
  if [ -d "$CONFIG_FILE" ]; then
    exit 1
  fi

  TEMP_CONFIG=$(mktemp "$MODULE_DIR/config.XXXXXX") || exit 1
  trap 'rm -f "$TEMP_CONFIG"' EXIT

  write_value PERSONALIZE_PATH "$PERSONALIZE_SCRIPT" > "$TEMP_CONFIG" || exit 1
  write_value PERSONALIZE_DIR "$DROP_IN_DIR" >> "$TEMP_CONFIG" || exit 1
  write_value PERSONALIZE_LOG_DIR "$MODULE_DIR/logs" >> "$TEMP_CONFIG" || exit 1

  mv "$TEMP_CONFIG" "$CONFIG_FILE"
)

# Runs the personalize script with no arguments, or explains how to create it.
run_personalize_script() {
  if [ ! -f "$PERSONALIZE_SCRIPT" ]; then
    printf "✨ %bYou don't have a personalize script!\n\n" "$BOLD"
    printf 'Create a script at %b%s%b and make it executable.\n' "$CODE" "$DISPLAY_PATH" "$RESET"
    printf 'It will run every time your workspace starts. Use it to install personal packages!\n\n'
  elif [ ! -x "$PERSONALIZE_SCRIPT" ]; then
    echo "🔐 Your personalize script isn't executable!"
    printf 'Make %b%s%b executable before restarting the workspace.\n' "$CODE" "$DISPLAY_PATH" "$RESET"
  else
    "$PERSONALIZE_SCRIPT" || {
      EXIT_STATUS=$?
      printf 'Personalize script %s failed with exit code %s.\n' "$PERSONALIZE_SCRIPT" "$EXIT_STATUS" >&2
    }
  fi
}

# Prints a notice and returns 1 when the drop-in path exists but is not a
# directory that can be listed. -L also catches a broken symlink, which -e
# does not. A missing drop-in directory is not an error.
drop_in_dir_is_usable() {
  if [ -e "$DROP_IN_DIR" ] || [ -L "$DROP_IN_DIR" ]; then
    if [ ! -d "$DROP_IN_DIR" ]; then
      printf 'Skipping non-directory drop-in path: %s\n' "$DROP_IN_DIR"
      return 1
    fi
    if [ ! -r "$DROP_IN_DIR" ] || [ ! -x "$DROP_IN_DIR" ]; then
      printf 'Skipping unreadable drop-in directory: %s\n' "$DROP_IN_DIR"
      return 1
    fi
  fi
  return 0
}

# Runs one drop-in script with the argument start if it is eligible, and
# records the first failing exit code in EXIT_STATUS.
run_drop_in_script() {
  DROP_IN_SCRIPT=$1

  # Skip names ending in ~, such as editor backups.
  case "$DROP_IN_SCRIPT" in
    *~) return 0 ;;
  esac

  if [ -L "$DROP_IN_SCRIPT" ] && [ ! -e "$DROP_IN_SCRIPT" ]; then
    printf 'Skipping broken drop-in script symlink: %s\n' "$DROP_IN_SCRIPT"
    return 0
  fi

  # Skip directories, other non-regular files, and the unexpanded glob
  # pattern of an empty or missing drop-in directory.
  if [ ! -f "$DROP_IN_SCRIPT" ]; then
    return 0
  fi

  if [ ! -x "$DROP_IN_SCRIPT" ]; then
    printf 'Skipping non-executable drop-in script: %s\n' "$DROP_IN_SCRIPT"
    return 0
  fi

  "$DROP_IN_SCRIPT" start || {
    SCRIPT_EXIT_CODE=$?
    printf 'Drop-in script %s failed with exit code %s.\n' "$DROP_IN_SCRIPT" "$SCRIPT_EXIT_CODE" >&2
    if [ "$EXIT_STATUS" -eq 0 ]; then
      EXIT_STATUS=$SCRIPT_EXIT_CODE
    fi
  }
}

# Runs the drop-in scripts in byte order of their file names.
run_drop_in_scripts() {
  if ! drop_in_dir_is_usable; then
    return 0
  fi

  # Expand the glob in the C locale so that names sort in byte order, then
  # restore LC_ALL, including whether it was set, so that user scripts run in
  # the caller's locale. The glob does not match hidden files.
  ORIGINAL_LC_ALL="$${LC_ALL-}"
  LC_ALL_WAS_SET="$${LC_ALL+x}"
  LC_ALL=C
  set -- "$DROP_IN_DIR/"*
  if [ "$LC_ALL_WAS_SET" = x ]; then
    LC_ALL=$ORIGINAL_LC_ALL
  else
    unset LC_ALL
  fi

  for DROP_IN_SCRIPT; do
    run_drop_in_script "$DROP_IN_SCRIPT"
  done
}

EXIT_STATUS=0

CONFIG_WRITTEN=1
if ! write_config; then
  CONFIG_WRITTEN=0
  printf 'Warning: failed to write personalize config file %s.\n' "$CONFIG_FILE" >&2
fi

run_personalize_script

if [ ! -f "$PERSONALIZE_SCRIPT" ] || [ ! -x "$PERSONALIZE_SCRIPT" ]; then
  printf 'Add executable drop-in scripts to %b%s.d%b; they receive start or stop.\n' "$CODE" "$DISPLAY_PATH" "$RESET"
  if [ "$CONFIG_WRITTEN" -eq 1 ]; then
    printf 'Find the module configuration at %s.\n' "$CONFIG_FILE"
  fi
fi

run_drop_in_scripts

exit "$EXIT_STATUS"
