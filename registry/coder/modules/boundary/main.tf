terraform {
  required_version = ">= 1.9"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

data "coder_workspace" "me" {}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "agent_firewall_version" {
  type        = string
  description = "Agent firewall version. When use_agent_firewall_directly is true, a release version should be provided or 'latest' for the latest release. When compile_agent_firewall_from_source is true, a valid git reference should be provided (tag, commit, branch)."
  default     = "latest"
}

variable "compile_agent_firewall_from_source" {
  type        = bool
  description = "Whether to compile agent firewall from source instead of using the official install script."
  default     = false
}

variable "use_agent_firewall_directly" {
  type        = bool
  description = "Whether to use agent firewall binary directly instead of `coder boundary` subcommand. When false (default), uses `coder boundary` subcommand. When true, installs and uses agent firewall binary from release."
  default     = false
}

variable "agent_firewall_config" {
  type        = string
  description = "Inline agent firewall configuration content (YAML). Overrides the module's default config. Mutually exclusive with agent_firewall_config_path."
  default     = null

  validation {
    condition     = !(var.agent_firewall_config != null && var.agent_firewall_config_path != null)
    error_message = "Only one of agent_firewall_config or agent_firewall_config_path may be set."
  }
}

variable "agent_firewall_config_path" {
  type        = string
  description = "Path to an existing agent firewall config file in the workspace. When set, no config is written and the agent_firewall_config_path output points to this path. Mutually exclusive with agent_firewall_config."
  default     = null
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing agent firewall."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing agent firewall."
  default     = null
}

variable "module_directory" {
  type        = string
  description = "Directory where the boundary module scripts will be located. Default is $HOME/.coder-modules/coder/boundary."
  default     = "$HOME/.coder-modules/coder/boundary"
}

locals {
  boundary_wrapper_path = "${var.module_directory}/scripts/boundary-wrapper.sh"

  # Extract domain from the Coder access URL for the default config
  # allowlist (e.g., "https://dev.coder.com/" -> "dev.coder.com").
  coder_domain = try(regex("^https?://([^/:]+)", data.coder_workspace.me.access_url)[0], "")

  # Config handling: resolve which config content to write and where
  # agent_firewall_config_path output points to.
  default_boundary_config = templatefile("${path.module}/config.yaml.tftpl", {
    CODER_DOMAIN     = local.coder_domain
    BOUNDARY_LOG_DIR = "${var.module_directory}/logs/boundary_logs"
  })
  boundary_config_content        = var.agent_firewall_config != null ? var.agent_firewall_config : local.default_boundary_config
  boundary_config_dir            = "${var.module_directory}/config"
  boundary_config_file_path      = "${local.boundary_config_dir}/config.yaml"
  effective_boundary_config_path = var.agent_firewall_config_path != null ? var.agent_firewall_config_path : local.boundary_config_file_path
  write_boundary_config          = var.agent_firewall_config_path == null

  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    BOUNDARY_VERSION             = var.agent_firewall_version
    COMPILE_BOUNDARY_FROM_SOURCE = tostring(var.compile_agent_firewall_from_source)
    USE_BOUNDARY_DIRECTLY        = tostring(var.use_agent_firewall_directly)
    MODULE_DIR                   = var.module_directory
    BOUNDARY_WRAPPER_PATH        = local.boundary_wrapper_path
    WRITE_BOUNDARY_CONFIG        = tostring(local.write_boundary_config)
    BOUNDARY_CONFIG_CONTENT_B64  = local.write_boundary_config ? base64encode(local.boundary_config_content) : ""
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

output "agent_firewall_wrapper_path" {
  description = "Path to the agent firewall wrapper script."
  value       = local.boundary_wrapper_path
}

output "agent_firewall_config_path" {
  description = "Effective path to the agent firewall config file."
  value       = local.effective_boundary_config_path
}

output "scripts" {
  description = "List of script names for coder exp sync coordination."
  value       = module.coder_utils.scripts
}
