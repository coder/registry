terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
    }
  }
}

variable "agent_id" {
  description = "The ID of a Coder agent."
  type        = string
}

variable "port" {
  description = "The loopback port used by the CloudCLI server and Coder app."
  type        = number
  default     = 3001

  validation {
    condition     = var.port >= 1024 && var.port <= 65535 && floor(var.port) == var.port
    error_message = "port must be an integer between 1024 and 65535."
  }
}

variable "cloudcli_version" {
  description = "Exact CloudCLI package version to install."
  type        = string
  default     = "1.35.0"

  validation {
    condition     = can(regex("^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$", var.cloudcli_version))
    error_message = "cloudcli_version must be an exact stable semantic version such as 1.35.0."
  }
}

variable "workspaces_root" {
  description = "Optional absolute directory that limits CloudCLI project discovery. When unset, CloudCLI uses the workspace user's home directory."
  type        = string
  default     = null

  validation {
    condition = var.workspaces_root == null ? true : (
      can(regex("^/[A-Za-z0-9._/-]+$", var.workspaces_root)) &&
      !can(regex("(^|/)\\.\\.(/|$)", var.workspaces_root))
    )
    error_message = "workspaces_root must be an absolute path containing only letters, numbers, dots, underscores, hyphens, and slashes, without parent-directory components."
  }
}

variable "order" {
  description = "The order determines the position of the app in the Coder UI. The lowest order is shown first."
  type        = number
  default     = null
}

variable "group" {
  description = "The name of a group that this app belongs to."
  type        = string
  default     = null
}

locals {
  icon_url          = "https://avatars.githubusercontent.com/u/252026187?s=200&v=4"
  module_directory  = "$HOME/.coder-modules/edd88-pixel/cloudcli"
  start_script_name = "edd88-pixel-cloudcli-start_script"
  start_script_path = "${local.module_directory}/scripts/start.sh"
  start_log_path    = "${local.module_directory}/logs/start.log"

  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_CLOUDCLI_VERSION = var.cloudcli_version
  })

  start_script = templatefile("${path.module}/scripts/start.sh.tftpl", {
    ARG_PORT                = tostring(var.port)
    ARG_WORKSPACES_ROOT_B64 = var.workspaces_root == null ? "" : base64encode(var.workspaces_root)
  })
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = local.module_directory
  display_name_prefix = "CloudCLI"
  icon                = local.icon_url
  install_script      = local.install_script
}

resource "coder_script" "start_script" {
  agent_id           = var.agent_id
  display_name       = "CloudCLI: Start Script"
  icon               = local.icon_url
  run_on_start       = true
  start_blocks_login = false

  script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    trap 'coder exp sync complete ${local.start_script_name}' EXIT

    coder exp sync want ${local.start_script_name} ${module.coder_utils.scripts[0]}
    coder exp sync start --timeout 30m ${local.start_script_name}

    echo -n '${base64encode(local.start_script)}' | base64 -d > ${local.start_script_path}
    chmod +x ${local.start_script_path}

    ${local.start_script_path} 2>&1 | tee ${local.start_log_path}
  EOT
}

# CloudCLI 1.35.0 uses root-relative API and WebSocket routes, so Coder's path proxy cannot serve it correctly.
resource "coder_app" "cloudcli" {
  agent_id     = var.agent_id
  slug         = "cloudcli"
  display_name = "CloudCLI"
  url          = "http://localhost:${var.port}"
  icon         = local.icon_url
  subdomain    = true
  share        = "owner"
  order        = var.order
  group        = var.group

  healthcheck {
    url       = "http://localhost:${var.port}/health"
    interval  = 5
    threshold = 6
  }
}

output "scripts" {
  description = "Ordered list of coder exp sync names produced by the CloudCLI install and start pipeline."
  value       = concat(module.coder_utils.scripts, [local.start_script_name])
}
