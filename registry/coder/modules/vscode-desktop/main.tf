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
  description = "VS Code extension IDs to pre-install on the workspace host."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for extension in var.extensions : trimspace(extension) != ""])
    error_message = "extensions must not contain empty extension IDs."
  }
}

locals {
  module_directory = "$HOME/.coder-modules/coder/vscode-desktop"
  server_directory = "${local.module_directory}/server"
}

module "vscode-desktop-core" {
  source  = "registry.coder.com/coder/vscode-desktop-core/coder"
  version = "1.2.0"

  agent_id = var.agent_id

  coder_app_icon         = "/icon/code.svg"
  coder_app_slug         = "vscode"
  coder_app_display_name = "VS Code Desktop"
  coder_app_order        = var.order
  coder_app_group        = var.group

  folder      = var.folder
  open_recent = var.open_recent
  protocol    = "vscode"
  config_dir  = "$HOME/.vscode"

  extensions     = var.extensions
  extensions_dir = "$HOME/.vscode-server/extensions"
  ide_cli_path   = "${local.server_directory}/bin/code-server"
  ide_cli_install_script = length(var.extensions) > 0 ? templatefile(
    "${path.module}/scripts/install-remote-server.sh.tftpl",
    {
      SERVER_DIRECTORY_B64 = base64encode(local.server_directory)
    },
  ) : null
}

output "vscode_url" {
  value       = module.vscode-desktop-core.ide_uri
  description = "VS Code Desktop URL."
}
