#!/usr/bin/env bash
set -euo pipefail

# Auto-detect which TypeScript tests to run based on changed files from paths-filter
# Uses paths-filter outputs from GitHub Actions:
#   ALL_CHANGED_FILES - all files changed in the PR (for logging)
#   SHARED_CHANGED - boolean indicating if shared infrastructure changed
#   MODULE_CHANGED_FILES - only files in registry/**/modules/** (for processing)
# Runs all tests if shared infrastructure changes
#
# This script only runs tests for changed modules. Documentation and template changes are ignored.

echo "==> Detecting changed files..."

if [[ -n "${ALL_CHANGED_FILES:-}" ]]; then
  echo "Changed files in PR:"
  echo "$ALL_CHANGED_FILES" | tr ' ' '\n' | sed 's/^/  - /'
  echo ""
fi

if [[ "${SHARED_CHANGED:-false}" == "true" ]]; then
  echo "==> Shared infrastructure changed"
  echo "==> Running all tests for safety"
  exec bun test
fi

if [[ -z "${MODULE_CHANGED_FILES:-}" ]]; then
  echo "✓ No module files changed, skipping tests"
  exit 0
fi

CHANGED_FILES=$(echo "$MODULE_CHANGED_FILES" | tr ' ' '\n')

MODULE_DIRS=()
while IFS= read -r file; do
  if [[ "$file" =~ \.(md|png|jpg|jpeg|svg)$ ]]; then
    continue
  fi

  if [[ "$file" =~ ^registry/([^/]+)/modules/([^/]+)/ ]]; then
    namespace="${BASH_REMATCH[1]}"
    module="${BASH_REMATCH[2]}"
    module_dir="registry/${namespace}/modules/${module}"

    if [[ -f "$module_dir/main.test.ts" ]] && [[ ! " ${MODULE_DIRS[*]} " =~ " $module_dir " ]]; then
      MODULE_DIRS+=("$module_dir")
    fi
  fi
done <<< "$CHANGED_FILES"

if [[ ${#MODULE_DIRS[@]} -eq 0 ]]; then
  echo "✓ No TypeScript tests to run"
  echo "  (documentation, templates, namespace files, or modules without tests)"
  exit 0
fi

echo "==> Running TypeScript tests for ${#MODULE_DIRS[@]} changed module(s):"
for dir in "${MODULE_DIRS[@]}"; do
  echo "  - $dir"
done
echo ""

exec bun test "${MODULE_DIRS[@]}"
