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

locals {
  boundary_script             = file("${path.module}/scripts/install.sh")
  module_directory            = "$HOME/.coder-modules/coder/boundary"
  boundary_script_destination = "${local.module_directory}/install.sh"
}

resource "coder_script" "boundary_script" {
  agent_id     = var.agent_id
  display_name = "Boundary Installation Script"
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail
    mkdir -p "$(dirname "${local.boundary_script_destination}")"
    echo -n '${base64encode(local.boundary_script)}' | base64 -d > "${local.boundary_script_destination}"
    chmod +x "${local.boundary_script_destination}"

    ARG_BOUNDARY_VERSION="${var.boundary_version}" \
    ARG_COMPILE_BOUNDARY_FROM_SOURCE="${var.compile_boundary_from_source}" \
    ARG_USE_BOUNDARY_DIRECTLY="${var.use_boundary_directly}" \
    ARG_MODULE_DIR="${local.module_directory}" \
    "${local.boundary_script_destination}"
EOT
}
