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
  description = "Whether to compile agent-firewall from source instead of using the official install script."
  default     = false
}

variable "use_agent_firewall_directly" {
  type        = bool
  description = "Whether to use agent-firewall binary directly instead of `coder agent-firewall` (or `coder boundary`) subcommand. When false (default), uses the coder subcommand. When true, installs and uses agent-firewall binary from release."
  default     = false
}

variable "agent_firewall_config" {
  type        = string
  description = "Inline agent-firewall configuration content (YAML). Overrides the module's default config. Mutually exclusive with agent_firewall_config_path."
  default     = null

  validation {
    condition     = !(var.agent_firewall_config != null && var.agent_firewall_config_path != null)
    error_message = "Only one of agent_firewall_config or agent_firewall_config_path may be set."
  }
}

variable "agent_firewall_config_path" {
  type        = string
  description = "Path to an existing agent-firewall config file in the workspace. When set, no config is written and the agent_firewall_config_path output points to this path. Mutually exclusive with agent_firewall_config."
  default     = null
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing agent-firewall."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing agent-firewall."
  default     = null
}

variable "module_directory" {
  type        = string
  description = "Directory where the agent-firewall module scripts will be located. Default is $HOME/.coder-modules/coder/agent-firewall."
  default     = "$HOME/.coder-modules/coder/agent-firewall"
}

locals {
  agent_firewall_wrapper_path = "${var.module_directory}/scripts/agent-firewall-wrapper.sh"

  # Extract domain from the Coder access URL for the default config
  # allowlist (e.g., "https://dev.coder.com/" -> "dev.coder.com").
  coder_domain = try(regex("^https?://([^/:]+)", data.coder_workspace.me.access_url)[0], "")

  # Config handling: resolve which config content to write and where
  # agent_firewall_config_path output points to.
  default_agent_firewall_config = templatefile("${path.module}/config.yaml.tftpl", {
    CODER_DOMAIN           = local.coder_domain
    AGENT_FIREWALL_LOG_DIR = "${var.module_directory}/logs/agent_firewall_logs"
  })
  agent_firewall_config_content        = var.agent_firewall_config != null ? var.agent_firewall_config : local.default_agent_firewall_config
  agent_firewall_config_dir            = "${var.module_directory}/config"
  agent_firewall_config_file_path      = "${local.agent_firewall_config_dir}/config.yaml"
  effective_agent_firewall_config_path = var.agent_firewall_config_path != null ? var.agent_firewall_config_path : local.agent_firewall_config_file_path
  write_agent_firewall_config          = var.agent_firewall_config_path == null

  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    AGENT_FIREWALL_VERSION             = var.agent_firewall_version
    COMPILE_AGENT_FIREWALL_FROM_SOURCE = tostring(var.compile_agent_firewall_from_source)
    USE_AGENT_FIREWALL_DIRECTLY        = tostring(var.use_agent_firewall_directly)
    MODULE_DIR                         = var.module_directory
    AGENT_FIREWALL_WRAPPER_PATH        = local.agent_firewall_wrapper_path
    WRITE_AGENT_FIREWALL_CONFIG        = tostring(local.write_agent_firewall_config)
    AGENT_FIREWALL_CONFIG_CONTENT_B64  = local.write_agent_firewall_config ? base64encode(local.agent_firewall_config_content) : ""
    AGENT_FIREWALL_CONFIG_DIR          = local.agent_firewall_config_dir
    AGENT_FIREWALL_CONFIG_FILE         = local.agent_firewall_config_file_path
  })
}

module "coder_utils" {
  source              = "registry.coder.com/coder/coder-utils/coder"
  version             = "0.0.1"
  agent_id            = var.agent_id
  display_name_prefix = "Agent Firewall"
  module_directory    = var.module_directory
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
}

output "agent_firewall_wrapper_path" {
  description = "Path to the agent-firewall wrapper script."
  value       = local.agent_firewall_wrapper_path
}

output "agent_firewall_config_path" {
  description = "Effective path to the agent-firewall config file."
  value       = local.effective_agent_firewall_config_path
}

output "scripts" {
  description = "List of script names for coder exp sync coordination."
  value       = module.coder_utils.scripts
}
