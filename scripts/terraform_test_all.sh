#!/usr/bin/env bash
set -euo pipefail

# Auto-detect which Terraform tests to run based on changed files from paths-filter
# Uses paths-filter outputs from GitHub Actions:
#   ALL_CHANGED_FILES - all files changed in the PR (for logging)
#   SHARED_CHANGED - boolean indicating if shared infrastructure changed
#   MODULE_CHANGED_FILES - only files in registry/**/modules/** (for processing)
# Runs all tests if shared infrastructure changes, or skips if no changes detected
#
# This script only runs tests for changed modules. Documentation and template changes are ignored.

run_dir() {
  local dir="$1"
  echo "==> Running terraform test in $dir"
  (cd "$dir" && terraform init -upgrade -input=false -no-color > /dev/null && terraform test -no-color -verbose)
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
  mapfile -t test_dirs < <(find . -type f -name "*.tftest.hcl" -print0 | xargs -0 -I{} dirname {} | sort -u)
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
      namespace="${BASH_REMATCH[1]}"
      module="${BASH_REMATCH[2]}"
      module_dir="registry/${namespace}/modules/${module}"

      if [[ -d "$module_dir" ]] && [[ ! " ${MODULE_DIRS[*]} " =~ " $module_dir " ]]; then
        MODULE_DIRS+=("$module_dir")
      fi
    fi
  done <<< "$CHANGED_FILES"

  if [[ ${#MODULE_DIRS[@]} -eq 0 ]]; then
    echo "✓ No Terraform tests to run"
    echo "  (documentation, templates, namespace files, or modules without changes)"
    exit 0
  fi

  echo "==> Finding .tftest.hcl files in ${#MODULE_DIRS[@]} changed module(s):"
  for dir in "${MODULE_DIRS[@]}"; do
    echo "  - $dir"
  done
  echo ""

  test_dirs=()
  for module_dir in "${MODULE_DIRS[@]}"; do
    while IFS= read -r test_file; do
      test_dir=$(dirname "$test_file")
      if [[ ! " ${test_dirs[*]} " =~ " $test_dir " ]]; then
        test_dirs+=("$test_dir")
      fi
    done < <(find "$module_dir" -type f -name "*.tftest.hcl")
  done
fi

if [[ ${#test_dirs[@]} -eq 0 ]]; then
  echo "✓ No .tftest.hcl tests found in changed modules"
  exit 0
fi

echo "==> Running terraform test in ${#test_dirs[@]} directory(ies)"
echo ""

status=0
for d in "${test_dirs[@]}"; do
  if ! run_dir "$d"; then
    status=1
  fi
done

exit $status
