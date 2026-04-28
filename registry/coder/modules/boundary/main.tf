terraform {
  required_version = ">= 1.9"

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

variable "boundary_config" {
  type        = string
  description = "Inline boundary configuration content (YAML). Overrides the module's default config. Mutually exclusive with boundary_config_path."
  default     = null

  validation {
    condition     = !(var.boundary_config != null && var.boundary_config_path != null)
    error_message = "Only one of boundary_config or boundary_config_path may be set."
  }
}

variable "boundary_config_path" {
  type        = string
  description = "Path to an existing boundary config file in the workspace. When set, no config is written and BOUNDARY_CONFIG points to this path. Mutually exclusive with boundary_config."
  default     = null
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
  boundary_wrapper_path = "${var.module_directory}/scripts/boundary-wrapper.sh"

  # Config handling: resolve which config content to write and where
  # BOUNDARY_CONFIG points to.
  default_boundary_config        = file("${path.module}/config.yaml")
  boundary_config_content        = var.boundary_config != null ? var.boundary_config : local.default_boundary_config
  boundary_config_dir            = "$HOME/.config/coder_boundary"
  boundary_config_file_path      = "${local.boundary_config_dir}/config.yaml"
  effective_boundary_config_path = var.boundary_config_path != null ? var.boundary_config_path : local.boundary_config_file_path
  write_boundary_config          = var.boundary_config_path == null

  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    BOUNDARY_VERSION             = var.boundary_version
    COMPILE_BOUNDARY_FROM_SOURCE = tostring(var.compile_boundary_from_source)
    USE_BOUNDARY_DIRECTLY        = tostring(var.use_boundary_directly)
    MODULE_DIR                   = var.module_directory
    BOUNDARY_WRAPPER_PATH        = local.boundary_wrapper_path
    WRITE_BOUNDARY_CONFIG        = tostring(local.write_boundary_config)
    BOUNDARY_CONFIG_CONTENT      = local.write_boundary_config ? local.boundary_config_content : ""
    BOUNDARY_CONFIG_DIR          = local.boundary_config_dir
    BOUNDARY_CONFIG_FILE         = local.boundary_config_file_path
  })
}

module "coder_utils" {
  source              = "registry.coder.com/coder/coder-utils/coder"
  version             = "0.0.1"
  agent_id            = var.agent_id
  display_name_prefix = "Boundary"
  module_directory    = var.module_directory
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
}

resource "coder_env" "boundary_wrapper_path" {
  agent_id = var.agent_id
  name     = "BOUNDARY_WRAPPER_PATH"
  value    = local.boundary_wrapper_path
}

resource "coder_env" "boundary_config" {
  agent_id = var.agent_id
  name     = "BOUNDARY_CONFIG"
  value    = local.effective_boundary_config_path
}

output "boundary_wrapper_path" {
  description = "Path to the boundary wrapper script."
  value       = local.boundary_wrapper_path
}

output "boundary_config_path" {
  description = "Effective path to the boundary config file."
  value       = local.effective_boundary_config_path
}

output "scripts" {
  description = "List of script names for coder exp sync coordination."
  value       = module.coder_utils.scripts
}
