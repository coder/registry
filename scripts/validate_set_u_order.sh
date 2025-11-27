#!/usr/bin/env bash

set -eo pipefail

# Validates that shell scripts source external files BEFORE enabling 'set -u'
# This prevents failures when sourced files (like /etc/bashrc) reference undefined variables
#
# Background: When 'set -u' is active, any reference to undefined variables causes the script to exit.
# System files like /etc/bashrc may reference variables (like $EUID) that aren't set in the script context.
#
# Correct pattern:
#   #!/bin/bash
#   source "$HOME/.bashrc"    # Source first
#   set -euo pipefail         # Then enable strict mode
#
# Incorrect pattern:
#   #!/bin/bash
#   set -euo pipefail         # set -u enabled first
#   source "$HOME/.bashrc"    # This may fail if bashrc references undefined vars

echo "==> Validating 'set -u' usage order in shell scripts..."

# Track if we found any issues
found_issues=0
total_checked=0

# Find all shell scripts
while IFS= read -r file; do
  # Skip if file doesn't exist (should not happen, but be safe)
  [[ -f "$file" ]] || continue

  # Check if file has both 'set -u' and 'source'/'.'
  # Look for: set -u, set -eu, set -euo, set -uo, etc.
  # Only check for sourcing common system/user files that might have undefined variables
  if grep -q "^set -[a-z]*u" "$file" && grep -q -E "^\s*(source|\.)\s+.*(\\\$HOME/\.bashrc|/etc/bashrc|/etc/os-release)" "$file"; then
    total_checked=$((total_checked + 1))

    # Get the first occurrence of each pattern with line numbers
    set_u_line=$(grep -n "^set -[a-z]*u" "$file" | head -1 | cut -d: -f1)
    source_line=$(grep -n -E "^\s*(source|\.)\s+.*(\\\$HOME/\.bashrc|/etc/bashrc|/etc/os-release)" "$file" | head -1 | cut -d: -f1)

    # Check if set -u comes before source (which is problematic)
    if [[ "$set_u_line" -lt "$source_line" ]]; then
      echo "ERROR: $file"
      echo "  'set -u' at line $set_u_line comes before 'source' at line $source_line"
      echo "  This may cause failures when sourcing system files with undefined variables."
      echo ""
      found_issues=$((found_issues + 1))
    fi
  fi
done < <(find registry -name "*.sh" -type f ! -path "*/node_modules/*" ! -path "*/.git/*" ! -path "*/.terraform/*" | sort)

# Report results
if [[ $found_issues -gt 0 ]]; then
  echo "================================================================"
  echo "FAILED: Found $found_issues script(s) with incorrect 'set -u' order"
  echo ""
  echo "Fix: Move 'source' statements BEFORE 'set -u' to prevent failures"
  echo "Example:"
  echo "  #!/bin/bash"
  echo "  source \"\$HOME/.bashrc\"    # Source first"
  echo "  set -euo pipefail           # Then enable strict mode"
  echo ""
  echo "See: SHELLCHECK_RESEARCH_REPORT.md for detailed analysis"
  echo "================================================================"
  exit 1
fi

if [[ $total_checked -eq 0 ]]; then
  echo "No scripts found with both 'set -u' and 'source' statements"
else
  echo "All $total_checked script(s) have correct 'set -u' ordering"
fi
