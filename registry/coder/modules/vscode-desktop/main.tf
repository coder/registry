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
  description = "A list of extensions to pre-install when the workspace starts. Use the format 'publisher.extension-name'."
  default     = []
}

variable "settings" {
  type        = map(any)
  description = "Machine-level VS Code settings to apply on the remote host. These are merged with existing machine settings on startup."
  default     = {}
}

variable "extensions_dir" {
  type        = string
  description = "Override the directory to store extensions in."
  default     = ""
}

locals {
  settings_b64 = length(var.settings) > 0 ? base64encode(jsonencode(var.settings)) : ""
}

module "vscode-desktop-core" {
  source  = "registry.coder.com/coder/vscode-desktop-core/coder"
  version = "1.0.2"

  agent_id = var.agent_id

  coder_app_icon         = "/icon/code.svg"
  coder_app_slug         = "vscode"
  coder_app_display_name = "VS Code Desktop"
  coder_app_order        = var.order
  coder_app_group        = var.group

  folder      = var.folder
  open_recent = var.open_recent
  protocol    = "vscode"
}

resource "coder_script" "vscode-desktop-extensions" {
  count    = length(var.extensions) > 0 || length(var.settings) > 0 ? 1 : 0
  agent_id = var.agent_id

  icon         = "/icon/code.svg"
  display_name = "VS Code Desktop Extensions"

  run_on_start       = true
  start_blocks_login = false

  script = templatefile("${path.module}/install-extensions.sh", {
    EXTENSIONS     = join(",", var.extensions)
    SETTINGS_B64   = local.settings_b64
    EXTENSIONS_DIR = var.extensions_dir
  })
}

output "vscode_url" {
  value       = module.vscode-desktop-core.ide_uri
  description = "VS Code Desktop URL."
}
