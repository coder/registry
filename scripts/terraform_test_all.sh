#!/usr/bin/env bash
set -euo pipefail

# Find all directories that contain any .tftest.hcl files and run terraform test in each

run_dir() {
  local dir="$1"
  echo "==> Running terraform test in $dir"
  (cd "$dir" && terraform init -upgrade -input=false -no-color > /dev/null && terraform test -no-color -verbose)
}

mapfile -t test_dirs < <(find . -type f -name "*.tftest.hcl" -print0 | xargs -0 -I{} dirname {} | sort -u)

if [[ ${#test_dirs[@]} -eq 0 ]]; then
  echo "No .tftest.hcl tests found."
  exit 0
fi

status=0
for d in "${test_dirs[@]}"; do
  if ! run_dir "$d"; then
    status=1
  fi
done

exit $status
