#!/usr/bin/env bash
set -euo pipefail

# Auto-detect which TypeScript tests to run based on git diff
# Falls back to running all tests if shared infrastructure changes
#
# This script only runs tests for changed modules. Documentation and template changes are ignored.

SHARED_FILES=(
  "test/"
  "package.json"
  "bun.lock"
  "bunfig.toml"
  "tsconfig.json"
  ".github/workflows/ci.yaml"
  "scripts/ts_test_auto.sh"
)

echo "==> Detecting changed files..."

if [[ -n "${GITHUB_BASE_REF:-}" ]]; then
  BASE_REF="origin/${GITHUB_BASE_REF}"
  echo "Detected GitHub Actions PR, comparing against: $BASE_REF"
else
  BASE_REF="origin/main"
  echo "Local development mode, comparing against: $BASE_REF"
fi

if ! CHANGED_FILES=$(git diff --name-only "${BASE_REF}...HEAD" 2> /dev/null); then
  echo "⚠️  Could not detect changes (git diff failed)"
  echo "==> Running all tests for safety"
  exec bun test
fi

if [[ -z "$CHANGED_FILES" ]]; then
  echo "✓ No files changed, skipping tests"
  exit 0
fi

echo "Changed files:"
echo "$CHANGED_FILES" | sed 's/^/  - /'
echo ""

for shared_file in "${SHARED_FILES[@]}"; do
  if echo "$CHANGED_FILES" | grep -q "^${shared_file}"; then
    echo "==> Shared infrastructure changed ($shared_file)"
    echo "==> Running all tests for safety"
    exec bun test
  fi
done

MODULE_DIRS=()
while IFS= read -r file; do
  if [[ "$file" =~ \.(md|png|jpg|jpeg|svg)$ ]]; then
    continue
  fi

  if [[ "$file" =~ ^registry/([^/]+)/modules/([^/]+)/ ]]; then
    namespace="${BASH_REMATCH[1]}"
    module="${BASH_REMATCH[2]}"
    module_dir="registry/${namespace}/modules/${module}"

    if [[ -f "$module_dir/main.test.ts" ]] && [[ ! " ${MODULE_DIRS[*]} " =~ " ${module_dir} " ]]; then
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
