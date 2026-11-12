#!/usr/bin/env bash

# Terraform renders this file with templatefile(). ACTION and PERSONALIZE_PATH
# are template values, and each braced shell expansion is written $${NAME}.

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
  *) ;;
esac

ACTION="${ACTION}"
DROP_IN_DIR="$PERSONALIZE_SCRIPT.d"
EXIT_STATUS=0

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
  # The C locale sorts the glob in byte order. Bash restores the caller's
  # locale when this function returns, so user scripts never see it.
  local LC_ALL=C
  DROP_IN_SCRIPTS=("$DROP_IN_DIR/"*)
}

run_drop_in_script() {
  local DROP_IN_SCRIPT=$1
  if [[ ! -f "$DROP_IN_SCRIPT" || "$DROP_IN_SCRIPT" = *~ ]]; then
    return
  fi
  if [[ ! -x "$DROP_IN_SCRIPT" ]]; then
    printf 'Skipping non-executable drop-in script: %s\n' "$DROP_IN_SCRIPT"
    return
  fi
  run_script "$DROP_IN_SCRIPT" "$ACTION"
}

if [[ "$ACTION" = start ]]; then
  printf 'Personalize runs your scripts when this workspace starts and stops:\n'
  printf '  %b%s%b runs at start.\n' "$CODE" "$DISPLAY_PATH" "$RESET"
  printf '  Executable files in %b%s.d%b run with "start" at start, and with "stop" at stop in reverse order.\n' "$CODE" "$DISPLAY_PATH" "$RESET"
  printf 'Docs: https://registry.coder.com/modules/coder/personalize\n\n'

  if [[ -f "$PERSONALIZE_SCRIPT" && -x "$PERSONALIZE_SCRIPT" ]]; then
    run_script "$PERSONALIZE_SCRIPT"
  elif [[ -f "$PERSONALIZE_SCRIPT" ]]; then
    echo "🔐 Your personalize script isn't executable!"
    printf 'Make %b%s%b executable before restarting the workspace.\n' "$CODE" "$DISPLAY_PATH" "$RESET"
  fi
fi

collect_drop_in_scripts
if [[ "$ACTION" = start ]]; then
  for DROP_IN_SCRIPT in "$${DROP_IN_SCRIPTS[@]}"; do
    run_drop_in_script "$DROP_IN_SCRIPT"
  done
else
  DROP_IN_COUNT=$${#DROP_IN_SCRIPTS[@]}
  for ((INDEX = DROP_IN_COUNT - 1; INDEX >= 0; INDEX--)); do
    run_drop_in_script "$${DROP_IN_SCRIPTS[INDEX]}"
  done
fi

exit "$EXIT_STATUS"
