#!/usr/bin/env bash
set -euo pipefail

# Script to validate coder_agent naming conventions across the registry
# This ensures consistency between templates and module documentation

ERRORS=0

echo "🔍 Linting coder_agent naming conventions..."
echo ""

# Check 1: Module README files should use coder_agent.main
echo "📝 Checking module README files..."
if grep -r 'coder_agent\.' registry/*/modules/*/README.md 2> /dev/null | grep -v 'coder_agent\.main' | grep -v 'agent_id' | grep -v 'coder_agent\.id' | grep -v '# ' | grep -E 'coder_agent\.[a-z_]+'; then
  echo "❌ ERROR: Module READMEs should reference 'coder_agent.main' in examples"
  echo "   Found references to other agent names above."
  ERRORS=$((ERRORS + 1))
else
  echo "✅ All module READMEs use 'coder_agent.main'"
fi
echo ""

# Check 2: Examples should use coder_agent.main
echo "📝 Checking example files..."
if [ -f "examples/templates/main.tf" ]; then
  if grep -q 'coder_agent\.' examples/templates/main.tf | grep -v 'coder_agent\.main' 2> /dev/null; then
    echo "❌ ERROR: examples/templates/main.tf should use 'coder_agent.main'"
    ERRORS=$((ERRORS + 1))
  else
    echo "✅ Example template uses 'coder_agent.main'"
  fi
fi
echo ""

# Check 3: Root documentation should use coder_agent.main
echo "📝 Checking root documentation..."
FILES_TO_CHECK=("README.md" "CONTRIBUTING.md")
for file in "${FILES_TO_CHECK[@]}"; do
  if [ -f "$file" ]; then
    if grep 'coder_agent\.' "$file" 2> /dev/null | grep -v 'coder_agent\.main' | grep -v '# ' | grep -v 'agent_id' | grep -v 'coder_agent\.id' | grep -E 'coder_agent\.[a-z_]+' > /dev/null 2>&1; then
      echo "❌ ERROR: $file should use 'coder_agent.main' in examples"
      ERRORS=$((ERRORS + 1))
    fi
  fi
done

if [ $ERRORS -eq 0 ]; then
  echo "✅ All documentation uses 'coder_agent.main'"
fi
echo ""

# Summary
if [ $ERRORS -eq 0 ]; then
  echo "✅ All linting checks passed!"
  exit 0
else
  echo "❌ Found $ERRORS linting error(s)"
  echo ""
  echo "ℹ️  Module documentation should use 'coder_agent.main' in examples"
  echo "   to match the most common template convention (78% of templates)."
  exit 1
fi
