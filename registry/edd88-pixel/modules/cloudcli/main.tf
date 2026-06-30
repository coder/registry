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
  module_directory = "$HOME/.coder-modules/edd88-pixel/cloudcli"

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
  icon                = "/icon/cloudcli.svg"
  install_script      = local.install_script
  start_script        = local.start_script
}

resource "coder_app" "cloudcli" {
  agent_id     = var.agent_id
  slug         = "cloudcli"
  display_name = "CloudCLI"
  url          = "http://localhost:${var.port}"
  icon         = "/icon/cloudcli.svg"
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
  value       = module.coder_utils.scripts
}
