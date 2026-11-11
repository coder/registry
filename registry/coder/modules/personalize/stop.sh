#!/usr/bin/env bash

# shellcheck disable=SC2016 # Terraform replaces this placeholder.
SCRIPT=$(printf '%s' '${PERSONALIZE_PATH}' | base64 -d) || {
  echo "Failed to decode the personalize script path." >&2
  exit 1
}
case "$SCRIPT" in
  \~) SCRIPT="$${HOME}" ;;
  \~/*) SCRIPT="$${HOME}/$${SCRIPT#??}" ;;
esac
case "$SCRIPT" in
  /*) ;;
  *) SCRIPT="$${PWD%/}/$SCRIPT" ;;
esac

if [ -e "$SCRIPT.d" ] || [ -L "$SCRIPT.d" ]; then
  if [ ! -d "$SCRIPT.d" ] || [ ! -r "$SCRIPT.d" ] || [ ! -x "$SCRIPT.d" ]; then
    printf 'Skipping unreadable drop-in directory: %s.d\n' "$SCRIPT"
    exit 0
  fi
fi

# Collect filenames in reverse byte order without changing user script locales.
ORIGINAL_LC_ALL="$${LC_ALL-}"
LC_ALL_WAS_SET="$${LC_ALL+x}"
LC_ALL=C
set --
for FILE in "$SCRIPT.d/"*; do
  set -- "$FILE" "$@"
done
if [ "$LC_ALL_WAS_SET" = x ]; then
  LC_ALL=$ORIGINAL_LC_ALL
else
  unset LC_ALL
fi

STATUS=0
for FILE; do
  case "$FILE" in *~) continue ;; esac
  if [ -L "$FILE" ] && [ ! -e "$FILE" ]; then
    printf 'Skipping broken drop-in script symlink: %s\n' "$FILE"
    continue
  fi
  [ -f "$FILE" ] || continue
  if [ ! -x "$FILE" ]; then
    printf 'Skipping non-executable drop-in script: %s\n' "$FILE"
    continue
  fi
  "$FILE" stop || {
    EXIT_CODE=$?
    printf 'Drop-in script %s failed with exit code %s.\n' "$FILE" "$EXIT_CODE" >&2
    if [ "$STATUS" -eq 0 ]; then STATUS=$EXIT_CODE; fi
  }
done
exit "$STATUS"
