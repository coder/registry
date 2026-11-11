#!/usr/bin/env bash

export LC_ALL=C
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

# Prepend each glob match to reverse byte order without splitting filenames.
set --
for FILE in "$SCRIPT.d/"*; do
  case "$FILE" in *~) continue ;; esac
  [ -f "$FILE" ] || continue
  set -- "$FILE" "$@"
done

STATUS=0
for FILE; do
  if [ ! -x "$FILE" ]; then
    printf 'Skipping non-executable personalize script: %s\n' "$FILE"
    continue
  fi
  "$FILE" stop || {
    EXIT_CODE=$?
    printf 'Personalize script %s failed with exit code %s.\n' "$FILE" "$EXIT_CODE" >&2
    if [ "$STATUS" -eq 0 ]; then STATUS=$EXIT_CODE; fi
  }
done
exit "$STATUS"
