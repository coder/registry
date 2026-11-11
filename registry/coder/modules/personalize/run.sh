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

write_value() {
  printf "%s='" "$1" \
    && printf '%s' "$2" | LC_ALL=C sed "s/'/'\\\\''/g" \
    && printf "'\n"
}

write_config() (
  mkdir -p "$MODULE_DIR" || exit 1
  [ ! -d "$CONFIG_FILE" ] || exit 1
  TEMP_CONFIG=$(mktemp "$MODULE_DIR/config.XXXXXX") || exit 1
  trap 'rm -f "$TEMP_CONFIG"' EXIT
  {
    write_value PERSONALIZE_PATH "$PERSONALIZE_SCRIPT" \
      && write_value PERSONALIZE_DIR "$DROP_IN_DIR" \
      && write_value PERSONALIZE_LOG_DIR "$MODULE_DIR/logs"
  } > "$TEMP_CONFIG" || exit 1
  mv "$TEMP_CONFIG" "$CONFIG_FILE"
)

CONFIG_WRITTEN=1
if ! write_config; then
  CONFIG_WRITTEN=0
  printf 'Warning: failed to write personalize config file %s.\n' "$CONFIG_FILE" >&2
fi

EXIT_STATUS=0
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
if [ ! -f "$PERSONALIZE_SCRIPT" ] || [ ! -x "$PERSONALIZE_SCRIPT" ]; then
  printf 'Add executable drop-in scripts to %b%s.d%b; they receive start or stop.\n' "$CODE" "$DISPLAY_PATH" "$RESET"
  if [ "$CONFIG_WRITTEN" -eq 1 ]; then
    printf 'Find the module configuration at %s.\n' "$CONFIG_FILE"
  fi
fi

if [ -e "$DROP_IN_DIR" ] || [ -L "$DROP_IN_DIR" ]; then
  if [ ! -d "$DROP_IN_DIR" ]; then
    printf 'Skipping non-directory drop-in path: %s\n' "$DROP_IN_DIR"
    exit "$EXIT_STATUS"
  fi
  if [ ! -r "$DROP_IN_DIR" ] || [ ! -x "$DROP_IN_DIR" ]; then
    printf 'Skipping unreadable drop-in directory: %s\n' "$DROP_IN_DIR"
    exit "$EXIT_STATUS"
  fi
fi

# Use byte order only while collecting filenames, not while running user scripts.
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
  "$DROP_IN_SCRIPT" start || {
    SCRIPT_EXIT_CODE=$?
    printf 'Drop-in script %s failed with exit code %s.\n' "$DROP_IN_SCRIPT" "$SCRIPT_EXIT_CODE" >&2
    if [ "$EXIT_STATUS" -eq 0 ]; then EXIT_STATUS=$SCRIPT_EXIT_CODE; fi
  }
done
exit "$EXIT_STATUS"
