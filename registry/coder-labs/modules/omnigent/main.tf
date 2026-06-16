terraform {
  required_version = ">= 1.9"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.12"
    }
  }
}

variable "agent_id" {
  description = "The ID of a Coder agent."
  type        = string
}

variable "icon" {
  description = "Icon for Omnigent scripts and app."
  type        = string
  default     = "../../../../.icons/omnigent.svg"
}

variable "port" {
  description = "Port the Omnigent server listens on inside the workspace."
  type        = number
  default     = 6767
  validation {
    condition     = var.port > 1024 && var.port < 65536
    error_message = "port must be between 1025 and 65535."
  }
}

variable "omnigent_version" {
  description = "Omnigent version to install. 'latest' installs the newest release."
  type        = string
  default     = "latest"
}

variable "share" {
  description = "Coder app share level."
  type        = string
  default     = "owner"
  validation {
    condition     = contains(["owner", "authenticated", "public"], var.share)
    error_message = "share must be one of: owner, authenticated, public."
  }
}

variable "order" {
  description = "Order for the Omnigent app in the Coder UI."
  type        = number
  default     = null
}

locals {
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_OMNIGENT_VERSION = var.omnigent_version
    ARG_PORT             = tostring(var.port)
  })
  start_script = templatefile("${path.module}/scripts/start.sh.tftpl", {
    ARG_PORT = tostring(var.port)
  })
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/.coder-modules/coder-labs/omnigent"
  display_name_prefix = "Omnigent"
  icon                = var.icon
  install_script      = local.install_script
  start_script        = local.start_script
}

resource "coder_app" "omnigent" {
  agent_id     = var.agent_id
  slug         = "omnigent"
  display_name = "Omnigent"
  url          = "http://localhost:${var.port}"
  icon         = var.icon
  subdomain    = true
  share        = var.share
  order        = var.order

  healthcheck {
    url       = "http://localhost:${var.port}/health"
    interval  = 15
    threshold = 3
  }
}

output "scripts" {
  description = "Ordered list of coder exp sync names produced by this module, in run order."
  value       = module.coder_utils.scripts
}

output "port" {
  description = "Port the Omnigent server is listening on."
  value       = var.port
}
