#!/usr/bin/env bash

# shellcheck disable=SC2016 # Terraform replaces this placeholder.
PERSONALIZE_SCRIPT=$(printf '%s' '${PERSONALIZE_PATH}' | base64 -d) || {
  echo "Failed to decode the personalize script path." >&2
  exit 1
}

case "$PERSONALIZE_SCRIPT" in
  \~) PERSONALIZE_SCRIPT="$${HOME}" ;;
  \~/*) PERSONALIZE_SCRIPT="$${HOME}/$${PERSONALIZE_SCRIPT#??}" ;;
esac
case "$PERSONALIZE_SCRIPT" in
  /*) ;;
  *) PERSONALIZE_SCRIPT="$${PWD%/}/$PERSONALIZE_SCRIPT" ;;
esac

DROP_IN_DIR="$PERSONALIZE_SCRIPT.d"

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

# Runs one drop-in script with the argument stop if it is eligible, and
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

  "$DROP_IN_SCRIPT" stop || {
    SCRIPT_EXIT_CODE=$?
    printf 'Drop-in script %s failed with exit code %s.\n' "$DROP_IN_SCRIPT" "$SCRIPT_EXIT_CODE" >&2
    if [ "$EXIT_STATUS" -eq 0 ]; then
      EXIT_STATUS=$SCRIPT_EXIT_CODE
    fi
  }
}

# Runs the drop-in scripts in reverse byte order of their file names.
run_drop_in_scripts() {
  if ! drop_in_dir_is_usable; then
    return 0
  fi

  # Expand the glob in the C locale so that names sort in byte order, then
  # restore LC_ALL, including whether it was set, so that user scripts run in
  # the caller's locale. The glob does not match hidden files. Prepending each
  # name to the positional parameters reverses the order.
  ORIGINAL_LC_ALL="$${LC_ALL-}"
  LC_ALL_WAS_SET="$${LC_ALL+x}"
  LC_ALL=C
  set --
  for DROP_IN_SCRIPT in "$DROP_IN_DIR/"*; do
    set -- "$DROP_IN_SCRIPT" "$@"
  done
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

run_drop_in_scripts

exit "$EXIT_STATUS"
