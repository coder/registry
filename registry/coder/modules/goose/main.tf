terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.12"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "icon" {
  type        = string
  description = "The icon to use for the install scripts."
  default     = "/icon/goose.svg"
}

variable "workdir" {
  type        = string
  description = "Optional project directory. When set, the module creates it if missing."
  default     = null
}

variable "install_goose" {
  type        = bool
  description = "Whether to install Goose with the official installer (https://goose-docs.ai/docs/getting-started/installation). When false, goose must already be on PATH."
  default     = true
}

variable "goose_version" {
  type        = string
  description = "The version of Goose to install, for example 'v1.54.0'. Use 'stable' for the latest stable release."
  default     = "stable"
}

variable "goose_provider" {
  type        = string
  description = "The provider to use for Goose (e.g., anthropic)."
}

variable "goose_model" {
  type        = string
  description = "The model to use for Goose (e.g., claude-sonnet-4-6)."
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Goose."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Goose."
  default     = null
}

variable "additional_extensions" {
  type        = string
  description = "Additional extensions configuration in YAML format to append to the config."
  default     = null
}

locals {
  workdir         = var.workdir != null ? trimsuffix(var.workdir, "/") : ""
  base_extensions = <<-EOT
developer:
  display_name: Developer
  enabled: true
  name: developer
  timeout: 300
  type: builtin
EOT

  # Add two spaces to each line of extensions to match YAML structure
  formatted_base        = "  ${replace(trimspace(local.base_extensions), "\n", "\n  ")}"
  additional_extensions = var.additional_extensions != null ? "\n  ${replace(trimspace(var.additional_extensions), "\n", "\n  ")}" : ""
  combined_extensions   = <<-EOT
extensions:
${local.formatted_base}${local.additional_extensions}
EOT
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_PROVIDER      = base64encode(var.goose_provider)
    ARG_MODEL         = base64encode(var.goose_model)
    ARG_GOOSE_CONFIG  = base64encode(local.combined_extensions)
    ARG_INSTALL       = tostring(var.install_goose)
    ARG_GOOSE_VERSION = base64encode(var.goose_version)
    ARG_WORKDIR       = local.workdir != "" ? base64encode(local.workdir) : ""
  })
  module_dir_name = ".coder-modules/coder/goose"

  # Create the workdir before the user's pre-install hook, as the agentapi
  # module did, so hooks that cd into it keep working on a fresh workspace.
  pre_install_script = var.pre_install_script == null || local.workdir == "" ? var.pre_install_script : <<-EOT
    #!/usr/bin/env bash
    set -o errexit
    mkdir -p '${local.workdir}'
    hook="$HOME/${local.module_dir_name}/scripts/pre_install_hook.sh"
    echo -n '${base64encode(var.pre_install_script)}' | base64 -d > "$hook"
    chmod +x "$hook"
    exec "$hook"
  EOT
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/${local.module_dir_name}"
  display_name_prefix = "Goose"
  icon                = var.icon
  pre_install_script  = local.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
}

output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module creates, in run order (pre_install, install, post_install). Scripts that were not configured are absent from the list."
  value       = module.coder_utils.scripts
}
