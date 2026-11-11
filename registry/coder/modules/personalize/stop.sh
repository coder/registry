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

if [ -e "$DROP_IN_DIR" ] || [ -L "$DROP_IN_DIR" ]; then
  if [ ! -d "$DROP_IN_DIR" ]; then
    printf 'Skipping non-directory drop-in path: %s\n' "$DROP_IN_DIR"
    exit 0
  fi
  if [ ! -r "$DROP_IN_DIR" ] || [ ! -x "$DROP_IN_DIR" ]; then
    printf 'Skipping unreadable drop-in directory: %s\n' "$DROP_IN_DIR"
    exit 0
  fi
fi

# Collect filenames in reverse byte order without changing user script locales.
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

EXIT_STATUS=0
for DROP_IN_SCRIPT; do
  case "$DROP_IN_SCRIPT" in *~) continue ;; esac
  if [ -L "$DROP_IN_SCRIPT" ] && [ ! -e "$DROP_IN_SCRIPT" ]; then
    printf 'Skipping broken drop-in script symlink: %s\n' "$DROP_IN_SCRIPT"
    continue
  fi
  [ -f "$DROP_IN_SCRIPT" ] || continue
  if [ ! -x "$DROP_IN_SCRIPT" ]; then
    printf 'Skipping non-executable drop-in script: %s\n' "$DROP_IN_SCRIPT"
    continue
  fi
  "$DROP_IN_SCRIPT" stop || {
    SCRIPT_EXIT_CODE=$?
    printf 'Drop-in script %s failed with exit code %s.\n' "$DROP_IN_SCRIPT" "$SCRIPT_EXIT_CODE" >&2
    if [ "$EXIT_STATUS" -eq 0 ]; then EXIT_STATUS=$SCRIPT_EXIT_CODE; fi
  }
done
exit "$EXIT_STATUS"
