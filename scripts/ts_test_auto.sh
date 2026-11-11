#!/usr/bin/env bash
set -euo pipefail

# Auto-detect which TypeScript tests to run based on changed files from paths-filter
# Uses paths-filter outputs from GitHub Actions:
#   ALL_CHANGED_FILES - all files changed in the PR (for logging)
#   SHARED_CHANGED - boolean indicating if shared infrastructure changed
#   MODULE_CHANGED_FILES - only files in registry/**/modules/** (for processing)
#   SHARD_INDEX / SHARD_COUNT - optional, 1-based shard of the test files (default 1/1)
# Runs all tests if shared infrastructure changes
#
# This script only runs tests for changed modules. Documentation and template changes are ignored.

TEST_TIMEOUT_MS="${TEST_TIMEOUT_MS:-30000}"
SHARD_INDEX="${SHARD_INDEX:-1}"
SHARD_COUNT="${SHARD_COUNT:-1}"

find_test_files() {
  find "$@" \( -name node_modules -o -name .git -o -name .terraform \) -prune -o \
    -type f \( -name "*.test.ts" -o -name "*_test.ts" -o -name "*.spec.ts" -o -name "*_spec.ts" \) -print
}

echo "==> Detecting changed files..."

if [[ -n "${ALL_CHANGED_FILES:-}" ]]; then
  echo "Changed files in PR:"
  echo "$ALL_CHANGED_FILES" | tr ' ' '\n' | sed 's/^/  - /'
  echo ""
fi

if [[ "${SHARED_CHANGED:-false}" == "true" ]]; then
  echo "==> Shared infrastructure changed"
  echo "==> Running all tests for safety"
  mapfile -t test_files < <(find_test_files . | sed 's#^\./##' | sort)
elif [[ -z "${MODULE_CHANGED_FILES:-}" ]]; then
  echo "✓ No module files changed, skipping tests"
  exit 0
else
  CHANGED_FILES=$(echo "$MODULE_CHANGED_FILES" | tr ' ' '\n')

  MODULE_DIRS=()
  while IFS= read -r file; do
    if [[ "$file" =~ \.(md|png|jpg|jpeg|svg)$ ]]; then
      continue
    fi

    if [[ "$file" =~ ^registry/([^/]+)/modules/([^/]+)/ ]]; then
      module_dir="registry/${BASH_REMATCH[1]}/modules/${BASH_REMATCH[2]}"

      if [[ -d "$module_dir" ]] && [[ ! " ${MODULE_DIRS[*]} " =~ " $module_dir " ]]; then
        MODULE_DIRS+=("$module_dir")
      fi
    fi
  done <<< "$CHANGED_FILES"

  test_files=()
  if [[ ${#MODULE_DIRS[@]} -gt 0 ]]; then
    mapfile -t test_files < <(find_test_files "${MODULE_DIRS[@]}" | sort)
  fi
fi

shard_files=()
for i in "${!test_files[@]}"; do
  if (((i % SHARD_COUNT) + 1 == SHARD_INDEX)); then
    shard_files+=("./${test_files[$i]}")
  fi
done

if [[ ${#shard_files[@]} -eq 0 ]]; then
  echo "✓ No TypeScript tests to run"
  echo "  (documentation, templates, namespace files, or modules without tests)"
  exit 0
fi

echo "==> Running ${#shard_files[@]} TypeScript test file(s) (shard ${SHARD_INDEX}/${SHARD_COUNT}):"
printf '  - %s\n' "${shard_files[@]}"
echo ""

# Without ./ bun treats a path as a substring filter (foo would also run foo-*).
exec bun test --timeout "$TEST_TIMEOUT_MS" "${shard_files[@]}"
