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
esac
case "$SCRIPT" in
  /*) ;;
  *) SCRIPT="$${PWD%/}/$SCRIPT" ;;
esac

MODULE_DIR="$HOME/.coder-modules/coder/personalize"

write_value() {
  printf "%s='" "$1" \
    && printf '%s' "$2" | LC_ALL=C sed "s/'/'\\\\''/g" \
    && printf "'\n"
}

write_config() (
  mkdir -p "$MODULE_DIR" || exit 1
  [ ! -d "$MODULE_DIR/config" ] || exit 1
  CONFIG_TMP=$(mktemp "$MODULE_DIR/config.XXXXXX") || exit 1
  trap 'rm -f "$CONFIG_TMP"' EXIT
  {
    write_value PERSONALIZE_PATH "$SCRIPT" \
      && write_value PERSONALIZE_DIR "$SCRIPT.d" \
      && write_value PERSONALIZE_LOG_DIR "$MODULE_DIR/logs"
  } > "$CONFIG_TMP" || exit 1
  mv "$CONFIG_TMP" "$MODULE_DIR/config"
)

CONFIG_WRITTEN=1
if ! write_config; then
  CONFIG_WRITTEN=0
  printf 'Warning: failed to write personalize config file %s/config.\n' "$MODULE_DIR" >&2
fi

STATUS=0
if [ ! -f "$SCRIPT" ]; then
  printf "✨ %bYou don't have a personalize script!\n\n" "$BOLD"
  printf 'Create a script at %b%s%b and make it executable.\n' "$CODE" "$DISPLAY_PATH" "$RESET"
  printf 'It will run every time your workspace starts. Use it to install personal packages!\n\n'
elif [ ! -x "$SCRIPT" ]; then
  echo "🔐 Your personalize script isn't executable!"
  printf 'Make %b%s%b executable before restarting the workspace.\n' "$CODE" "$DISPLAY_PATH" "$RESET"
else
  "$SCRIPT" || {
    STATUS=$?
    printf 'Personalize script %s failed with exit code %s.\n' "$SCRIPT" "$STATUS" >&2
  }
fi
if [ ! -f "$SCRIPT" ] || [ ! -x "$SCRIPT" ]; then
  printf 'Add executable drop-in scripts to %b%s.d%b; they receive start or stop.\n' "$CODE" "$DISPLAY_PATH" "$RESET"
  if [ "$CONFIG_WRITTEN" -eq 1 ]; then
    printf 'Find the module configuration at %s/config.\n' "$MODULE_DIR"
  fi
fi

if [ -e "$SCRIPT.d" ] || [ -L "$SCRIPT.d" ]; then
  if [ ! -d "$SCRIPT.d" ]; then
    printf 'Skipping non-directory drop-in path: %s.d\n' "$SCRIPT"
    exit "$STATUS"
  fi
  if [ ! -r "$SCRIPT.d" ] || [ ! -x "$SCRIPT.d" ]; then
    printf 'Skipping unreadable drop-in directory: %s.d\n' "$SCRIPT"
    exit "$STATUS"
  fi
fi

# Use byte order only while collecting filenames, not while running user scripts.
ORIGINAL_LC_ALL="$${LC_ALL-}"
LC_ALL_WAS_SET="$${LC_ALL+x}"
LC_ALL=C
set -- "$SCRIPT.d/"*
if [ "$LC_ALL_WAS_SET" = x ]; then
  LC_ALL=$ORIGINAL_LC_ALL
else
  unset LC_ALL
fi

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
  "$FILE" start || {
    EXIT_CODE=$?
    printf 'Drop-in script %s failed with exit code %s.\n' "$FILE" "$EXIT_CODE" >&2
    if [ "$STATUS" -eq 0 ]; then STATUS=$EXIT_CODE; fi
  }
done
exit "$STATUS"
