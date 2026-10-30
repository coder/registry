#!/usr/bin/env bash
# Workspace startup script. Runs as the coder user inside the workspace pod.
set -euo pipefail

# Trust the home directory in Kiro so it opens without a workspace trust prompt.
mkdir -p "$HOME/.kiro/settings"
cat > "$HOME/.kiro/settings/trusted-workspaces.json" << EOF
{
  "trustedFolders": [
    "$HOME"
  ]
}
EOF

echo "Workspace startup completed."
