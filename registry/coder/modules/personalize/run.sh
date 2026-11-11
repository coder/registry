#!/usr/bin/env bash

# Terraform encodes the path and requires $$ for braced shell expansions.
# shellcheck disable=SC2016 # Terraform replaces this placeholder.
PERSONALIZE_SCRIPT=$(printf '%s' '${PERSONALIZE_PATH}' | base64 -d) || exit 1
DISPLAY_PATH=$PERSONALIZE_SCRIPT
ACTION="${ACTION}"
case "$PERSONALIZE_SCRIPT" in
  \~) PERSONALIZE_SCRIPT="$HOME" ;;
  \~/*) PERSONALIZE_SCRIPT="$HOME/$${PERSONALIZE_SCRIPT#??}" ;;
esac
DROP_IN_DIR="$PERSONALIZE_SCRIPT.d"
MODULE_DIR="$HOME/.coder-modules/coder/personalize"
EXIT_STATUS=0

write_config() (
  mkdir -p "$MODULE_DIR" || exit 1
  local TEMP_CONFIG
  TEMP_CONFIG=$(mktemp "$MODULE_DIR/config.XXXXXX") || exit 1
  # Rename a complete file; remove the temporary file if writing fails.
  trap 'rm -f "$TEMP_CONFIG"' EXIT
  printf 'PERSONALIZE_PATH=%q\nPERSONALIZE_DIR=%q\nPERSONALIZE_LOG_DIR=%q\n' \
    "$PERSONALIZE_SCRIPT" "$DROP_IN_DIR" "$MODULE_DIR/logs" > "$TEMP_CONFIG" || exit 1
  mv "$TEMP_CONFIG" "$MODULE_DIR/config"
)

run_script() {
  local SCRIPT_EXIT_CODE=0
  "$@" || SCRIPT_EXIT_CODE=$?
  if [[ "$SCRIPT_EXIT_CODE" -ne 0 ]]; then
    printf 'Script %s failed with exit code %s.\n' "$1" "$SCRIPT_EXIT_CODE" >&2
    if [[ "$EXIT_STATUS" -eq 0 ]]; then
      EXIT_STATUS=$SCRIPT_EXIT_CODE
    fi
  fi
}

collect_drop_in_scripts() {
  # Bash restores the caller's locale when this function returns.
  local LC_ALL=C
  DROP_IN_SCRIPTS=("$DROP_IN_DIR/"*)
}

if [[ "$ACTION" = start ]]; then
  write_config || printf 'Warning: failed to write personalize config file %s/config.\n' "$MODULE_DIR" >&2

  BOLD='\033[0;1m'
  CODE='\033[36;40;1m'
  RESET='\033[0m'
  if [[ -f "$PERSONALIZE_SCRIPT" && -x "$PERSONALIZE_SCRIPT" ]]; then
    run_script "$PERSONALIZE_SCRIPT"
  elif [[ -e "$PERSONALIZE_SCRIPT" && ! -x "$PERSONALIZE_SCRIPT" ]]; then
    echo "🔐 Your personalize script isn't executable!"
    printf 'Make %b%s%b executable before restarting the workspace.\n' "$CODE" "$DISPLAY_PATH" "$RESET"
  elif [[ ! -e "$PERSONALIZE_SCRIPT" && ! -e "$DROP_IN_DIR" ]]; then
    printf "✨ %bYou don't have a personalize script!\n\n" "$BOLD"
    printf 'Create a script at %b%s%b and make it executable.\n' "$CODE" "$DISPLAY_PATH" "$RESET"
    printf 'It will run every time your workspace starts. Use it to install personal packages!\n\n'
    printf 'Add executable drop-in scripts to %b%s.d%b; find the module configuration at %s/config.\n' "$CODE" "$DISPLAY_PATH" "$RESET" "$MODULE_DIR"
  fi
fi

collect_drop_in_scripts
DROP_IN_COUNT="$${#DROP_IN_SCRIPTS[@]}"
INDEX=0
STEP=1
if [[ "$ACTION" = stop ]]; then
  INDEX=$((DROP_IN_COUNT - 1))
  STEP=-1
fi
for (( ; INDEX >= 0 && INDEX < DROP_IN_COUNT; INDEX += STEP)); do
  DROP_IN_SCRIPT="$${DROP_IN_SCRIPTS[INDEX]}"
  if [[ ! -f "$DROP_IN_SCRIPT" || "$DROP_IN_SCRIPT" = *~ ]]; then
    continue
  fi
  if [[ ! -x "$DROP_IN_SCRIPT" ]]; then
    printf 'Skipping non-executable drop-in script: %s\n' "$DROP_IN_SCRIPT"
  else
    run_script "$DROP_IN_SCRIPT" "$ACTION"
  fi
done
exit "$EXIT_STATUS"
