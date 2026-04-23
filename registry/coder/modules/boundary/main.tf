terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

# Add required variables for your modules and remove any unneeded variables
variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "boundary_version" {
  type        = string
  description = "Boundary version. When use_boundary_directly is true, a release version should be provided or 'latest' for the latest release. When compile_boundary_from_source is true, a valid git reference should be provided (tag, commit, branch)."
  default     = "latest"
}

variable "compile_boundary_from_source" {
  type        = bool
  description = "Whether to compile boundary from source instead of using the official install script."
  default     = false
}

variable "use_boundary_directly" {
  type        = bool
  description = "Whether to use boundary binary directly instead of `coder boundary` subcommand. When false (default), uses `coder boundary` subcommand. When true, installs and uses boundary binary from release."
  default     = false
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Boundary."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Boundary."
  default     = null
}

variable "module_directory" {
  type        = string
  description = "Directory where the boundary module scripts will be located. Default is $HOME/.coder-modules/coder/boundary."
  default     = "$HOME/.coder-modules/coder/boundary"
}

locals {
  boundary_script_path  = "${path.module}/scripts/install.sh"
  boundary_wrapper_path = "${var.module_directory}/scripts/boundary-wrapper.sh"
}

module "coder_utils" {
  source              = "registry.coder.com/coder/coder-utils/coder"
  version             = "1.2.0"
  agent_id            = var.agent_id
  agent_name          = "coder_boundary"
  display_name_prefix = "Boundary"
  module_directory    = var.module_directory
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail
    chmod +x "${local.boundary_script_path}"

    ARG_BOUNDARY_VERSION="${var.boundary_version}" \
    ARG_COMPILE_BOUNDARY_FROM_SOURCE="${var.compile_boundary_from_source}" \
    ARG_USE_BOUNDARY_DIRECTLY="${var.use_boundary_directly}" \
    ARG_MODULE_DIR="${var.module_directory}" \
    ARG_BOUNDARY_WRAPPER_PATH="${local.boundary_wrapper_path}" \
    "${local.boundary_script_path}"
EOT
}

resource "coder_env" "boundary_wrapper_path" {
  agent_id = var.agent_id
  name     = "BOUNDARY_WRAPPER_PATH"
  value    = local.boundary_wrapper_path
}

output "boundary_wrapper_path" {
  description = "Path to the boundary wrapper script."
  value       = local.boundary_wrapper_path
}

output "scripts" {
  value = module.coder_utils.scripts
}
