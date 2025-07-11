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
  description = "A list of VS Code extensions to install. Extensions should be specified in the format 'publisher.extension-name'."
  default     = []
  
  validation {
    condition = alltrue([
      for ext in var.extensions : can(regex("^[a-zA-Z0-9][a-zA-Z0-9\\-_]*\\.[a-zA-Z0-9][a-zA-Z0-9\\-_]*$", ext))
    ])
    error_message = "Extensions must be in the format 'publisher.extension-name' (e.g., 'ms-python.python')."
  }
}

variable "settings" {
  type        = any
  description = "A map of VS Code settings to apply to the workspace. These settings will be written to the workspace's settings.json file."
  default     = {}
}

variable "install_extensions" {
  type        = bool
  description = "Whether to automatically install the specified extensions when the workspace starts."
  default     = true
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Script to install extensions and configure settings
resource "coder_script" "vscode_desktop_setup" {
  count        = var.install_extensions && (length(var.extensions) > 0 || length(var.settings) > 0) ? 1 : 0
  agent_id     = var.agent_id
  display_name = "VS Code Desktop Setup"
  icon         = "/icon/code.svg"
  run_on_start = true
  run_on_stop  = false
  timeout      = 300

  script = templatefile("${path.module}/setup.sh", {
    EXTENSIONS = jsonencode(var.extensions)
    SETTINGS   = jsonencode(var.settings)
    FOLDER     = var.folder
  })
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
