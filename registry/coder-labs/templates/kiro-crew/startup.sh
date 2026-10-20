#!/usr/bin/env bash
# Workspace startup script. Runs as the coder user inside the workspace pod.
set -euo pipefail

mkdir -p "$HOME/.ssh" "$HOME/bin" "$HOME/.local/bin"
chmod 700 "$HOME/.ssh"
ssh-keyscan -t ed25519,rsa github.com >> "$HOME/.ssh/known_hosts" 2> /dev/null || echo "Warning: could not fetch GitHub host keys."
chmod 600 "$HOME/.ssh/known_hosts" 2> /dev/null || true

# Point Kiro at the Coder MCP server so agents can work with Coder itself.
# CODER_URL and CODER_SESSION_TOKEN are set by the coder-login module.
if [ -n "${CODER_URL:-}" ] && [ -n "${CODER_SESSION_TOKEN:-}" ]; then
  echo "Configuring the Coder MCP server for Kiro..."
  mkdir -p "$HOME/.kiro/settings"
  CODER_MCP_URL="${CODER_URL%/}/api/experimental/mcp/http"
  cat > "$HOME/.kiro/settings/mcp.json" << EOF
{
  "mcpServers": {
    "coder": {
      "url": "$CODER_MCP_URL",
      "headers": {
        "Authorization": "Bearer $CODER_SESSION_TOKEN"
      },
      "autoApprove": [
        "coder_workspace_edit_file",
        "coder_workspace_read_file",
        "coder_get_task_status",
        "coder_workspace_write_file",
        "coder_workspace_ls",
        "coder_workspace_bash",
        "coder_get_task_logs",
        "coder_list_templates",
        "coder_create_task",
        "coder_get_authenticated_user",
        "coder_delete_task",
        "coder_send_task_input",
        "coder_list_workspaces",
        "coder_workspace_edit_files",
        "coder_workspace_list_apps",
        "coder_workspace_port_forward",
        "coder_create_workspace_build",
        "coder_template_version_parameters"
      ]
    }
  }
}
EOF
  chmod 600 "$HOME/.kiro/settings/mcp.json"
else
  echo "CODER_URL or CODER_SESSION_TOKEN is not set; skipping Coder MCP configuration."
fi

# Trust the home directory in code-server and Kiro so they open without a
# workspace trust prompt.
mkdir -p "$HOME/.local/share/code-server/User"
cat > "$HOME/.local/share/code-server/User/settings.json" << 'EOF'
{
  "security.workspace.trust.enabled": true,
  "security.workspace.trust.startupPrompt": "never",
  "security.workspace.trust.emptyWindow": false,
  "security.workspace.trust.untrustedFiles": "open"
}
EOF

mkdir -p "$HOME/.kiro/settings"
cat > "$HOME/.kiro/settings/trusted-workspaces.json" << EOF
{
  "trustedFolders": [
    "$HOME"
  ]
}
EOF

echo "Workspace startup completed."
