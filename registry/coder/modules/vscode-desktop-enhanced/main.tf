terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "folder" {
  type        = string
  description = "The folder to open in VS Code."
  default     = ""
}

variable "open_recent" {
  type        = bool
  description = "Open the most recent workspace or folder. Falls back to the folder if there is no recent workspace or folder to open."
  default     = false
}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  default     = null
}

variable "group" {
  type        = string
  description = "The name of a group that this app belongs to."
  default     = null
}

variable "extensions" {
  type        = list(string)
  description = "List of VS Code extension IDs to pre-install (e.g., ['ms-python.python', 'ms-vscode.vscode-typescript-next'])"
  default     = []
}

variable "settings" {
  type        = string
  description = "VS Code settings in JSON format to be applied to the workspace"
  default     = "{}"
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Script to install extensions and apply settings
resource "coder_script" "vscode_setup" {
  count           = length(var.extensions) > 0 || var.settings != "{}" ? 1 : 0
  agent_id        = var.agent_id
  display_name    = "VS Code Setup"
  icon            = "/icon/code.svg"
  script          = join("\n", [
    "#!/bin/bash",
    "set -euo pipefail",
    "",
    "# VS Code Setup Script for Coder Workspaces",
    "VSCODE_USER_DIR=\"$HOME/.vscode-server\"",
    "EXTENSIONS_DIR=\"$VSCODE_USER_DIR/extensions\"",
    "SETTINGS_DIR=\"$VSCODE_USER_DIR/data/Machine\"",
    "SETTINGS_FILE=\"$SETTINGS_DIR/settings.json\"",
    "",
    "# Ensure VS Code server directories exist",
    "mkdir -p \"$EXTENSIONS_DIR\"",
    "mkdir -p \"$SETTINGS_DIR\"",
    "",
    "echo \"🚀 Starting VS Code setup...\"",
    "",
    "# Function to install a single extension",
    "install_extension() {",
    "    local extension=\"$1\"",
    "    echo \"🔧 Installing extension: $extension\"",
    "    ",
    "    # Check if code command is available",
    "    if ! command -v code &> /dev/null; then",
    "        echo \"⚠️  VS Code CLI not found. Attempting to download...\"",
    "        if command -v curl &> /dev/null; then",
    "            echo \"📥 Downloading VS Code CLI...\"",
    "            curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' --output vscode_cli.tar.gz",
    "            tar -xf vscode_cli.tar.gz",
    "            chmod +x code",
    "            sudo mv code /usr/local/bin/ 2>/dev/null || mv code /tmp/code",
    "            export PATH=\"/tmp:$PATH\"",
    "        else",
    "            echo \"❌ curl not available. Cannot install VS Code CLI.\"",
    "            return 1",
    "        fi",
    "    fi",
    "    ",
    "    code --install-extension \"$extension\" --force || {",
    "        echo \"⚠️  Failed to install extension: $extension\"",
    "        return 1",
    "    }",
    "    echo \"✅ Installed: $extension\"",
    "}",
    "",
    "# Install extensions",
    length(var.extensions) > 0 ? join("\n", [for ext in var.extensions : "install_extension \"${ext}\""]) : "echo \"📦 No extensions to install\"",
    "",
    "# Apply settings",
    var.settings != "{}" ? join("\n", [
      "echo \"⚙️  Applying VS Code settings...\"",
      "if [ ! -f \"$SETTINGS_FILE\" ]; then",
      "    echo \"{}\" > \"$SETTINGS_FILE\"",
      "fi",
      "",
      "# Write settings to file",
      "cat > \"$SETTINGS_FILE\" << 'SETTINGS_EOF'",
      var.settings,
      "SETTINGS_EOF",
      "echo \"✅ Settings applied successfully\""
    ]) : "echo \"⚙️  No custom settings to apply\"",
    "",
    "# Set up workspace configuration",
    length(var.extensions) > 0 ? join("\n", [
      "echo \"📁 Setting up workspace configuration...\"",
      "workspace_dir=\"${var.folder != "" ? var.folder : "$PWD"}\"",
      "vscode_dir=\"$workspace_dir/.vscode\"",
      "",
      "if [ ! -d \"$vscode_dir\" ]; then",
      "    mkdir -p \"$vscode_dir\"",
      "    echo \"📂 Created .vscode directory\"",
      "fi",
      "",
      "# Create extensions.json with recommended extensions",
      "cat > \"$vscode_dir/extensions.json\" << 'EOF'",
      "{",
      "    \"recommendations\": [",
      join(",\n", [for i, ext in var.extensions : "        \"${ext}\""]),
      "    ]",
      "}",
      "EOF",
      "echo \"📋 Created extensions.json with recommendations\""
    ]) : "",
    "",
    "echo \"🎉 VS Code setup completed successfully!\"",
    "echo \"💡 Extensions and settings will be available when you connect with VS Code Desktop\""
  ])
  run_on_start    = true
  run_on_stop     = false
}

resource "coder_app" "vscode" {
  agent_id     = var.agent_id
  external     = true
  icon         = "/icon/code.svg"
  slug         = "vscode"
  display_name = "VS Code Desktop"
  order        = var.order
  group        = var.group

  url = join("", [
    "vscode://coder.coder-remote/open",
    "?owner=",
    data.coder_workspace_owner.me.name,
    "&workspace=",
    data.coder_workspace.me.name,
    var.folder != "" ? join("", ["&folder=", var.folder]) : "",
    var.open_recent ? "&openRecent" : "",
    "&url=",
    data.coder_workspace.me.access_url,
    "&token=$SESSION_TOKEN",
  ])
}

output "vscode_url" {
  value       = coder_app.vscode.url
  description = "VS Code Desktop URL."
}

output "extensions_installed" {
  value       = var.extensions
  description = "List of VS Code extensions that will be installed."
}

output "settings_applied" {
  value       = var.settings != "{}" ? "Custom settings applied" : "No custom settings"
  description = "Status of VS Code settings configuration."
}
