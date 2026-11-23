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

variable "backupdrill_version" {
  description = "Version of the backupdrill npm package to install: a major (\"2\"), major.minor (\"2.7\"), an exact version (\"2.7.1\") or \"latest\". The default \"2\" installs the newest 2.x release."
  type        = string
  default     = "2"

  validation {
    condition     = can(regex("^(latest|[0-9]+(\\.[0-9]+){0,2})$", var.backupdrill_version))
    error_message = "backupdrill_version must be \"latest\" or a version like \"2\", \"2.7\" or \"2.7.1\"."
  }
}

variable "npm_registry_url" {
  description = "npm registry to install backupdrill from, for example an internal mirror. Leave empty to use npm's configured registry."
  type        = string
  default     = ""

  validation {
    condition     = var.npm_registry_url == "" || can(regex("^https?://[^\\s']+$", var.npm_registry_url))
    error_message = "npm_registry_url must be an http(s) URL when set."
  }
}

variable "icon" {
  description = "Icon shown next to the install script in the Coder UI."
  type        = string
  default     = "/icon/backupdrill.svg"
}

locals {
  module_directory = "$HOME/.coder-modules/supertj/backupdrill"

  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_BACKUPDRILL_VERSION = var.backupdrill_version
    ARG_NPM_REGISTRY_URL    = var.npm_registry_url
  })
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.2"

  agent_id            = var.agent_id
  module_directory    = local.module_directory
  display_name_prefix = "backupdrill"
  icon                = var.icon
  install_script      = local.install_script
}

output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module creates, in run order."
  value       = module.coder_utils.scripts
}
