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

# New variable for extensions
variable "extensions" {
  type        = list(string)
  description = "A list of VS Code extension IDs to install."
  default     = []
}

# New variable for settings
variable "settings" {
  type        = string
  description = "A JSON string of settings to apply to VS Code."
  default     = ""
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# This script will install extensions and apply settings
resource "coder_script" "setup_vscode" {
  # Only run if extensions or settings are provided
  count = length(var.extensions) > 0 || var.settings != "" ? 1 : 0

  agent_id     = var.agent_id
  display_name = "Setup VS Code"
  icon         = "/icon/code.svg"
  run_on_start = true

  script = <<-EOT
    #!/bin/bash
    set -e

    # Wait for code-server to be available
    # VS Code Server is installed by the Coder agent, which can take a moment.
    for i in {1..30}; do
      if command -v code &> /dev/null; then
        break
      fi
      echo "Waiting for 'code' command..."
      sleep 1
    done
    if ! command -v code &> /dev/null; then
      echo "'code' command not found after 30s"
      exit 1
    fi

    # Install extensions
    %{ for ext in var.extensions ~}
    code --install-extension ${ext} --force
    %{ endfor ~}

    # Apply settings
    %{ if var.settings != "" ~}
    # Path for settings for remote VS Code Desktop
    SETTINGS_DIR="/home/coder/.vscode-server/data/Machine"
    mkdir -p "$SETTINGS_DIR"
    cat <<'EOF' > "$SETTINGS_DIR/settings.json"
    ${var.settings}
    EOF
    %{ endif ~}
  EOT
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