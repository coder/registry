terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.0"
    }
  }
}

variable "agent_id" {
  description = "The ID of a Coder agent."
  type        = string
}

variable "icon" {
  description = "The icon to use for the module."
  type        = string
  default     = "/icon/supabase.svg"
}

variable "external_auth_id" {
  description = "Supabase external auth provider ID configured in Coder."
  type        = string
  default     = "supabase"
}

variable "use_external_auth" {
  description = "Use Coder external auth for Supabase authentication."
  type        = bool
  default     = true
}

variable "access_token" {
  description = "Supabase personal access token. Ignored if use_external_auth is true."
  type        = string
  default     = ""
  sensitive   = true
}

variable "install_method" {
  description = "Installation method: 'auto' (detect best), 'brew', 'scoop' (Windows), or 'binary'."
  type        = string
  default     = "auto"
  validation {
    condition     = contains(["auto", "brew", "scoop", "binary"], var.install_method)
    error_message = "install_method must be 'auto', 'brew', 'scoop', or 'binary'."
  }
}

variable "supabase_version" {
  description = "Supabase CLI version to install. Use 'latest' for most recent."
  type        = string
  default     = "latest"
}

variable "db_password" {
  description = "Database password for non-interactive db commands (optional)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "pre_install_script" {
  description = "Custom script to run before installing Supabase CLI."
  type        = string
  default     = null
}

variable "post_install_script" {
  description = "Custom script to run after installing Supabase CLI."
  type        = string
  default     = null
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

# External auth data source - only used when use_external_auth is true
data "coder_external_auth" "supabase" {
  count = var.use_external_auth ? 1 : 0
  id    = var.external_auth_id
}

locals {
  module_dir = "$HOME/.coder-modules/coder/supabase"

  # Determine the access token to use
  access_token = var.use_external_auth ? try(data.coder_external_auth.supabase[0].access_token, "") : var.access_token

  # Render the install script
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL_METHOD = var.install_method
    ARG_VERSION        = var.supabase_version
  })
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = local.module_dir
  display_name_prefix = "Supabase"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  install_script      = local.install_script
  post_install_script = var.post_install_script
}

# Set SUPABASE_ACCESS_TOKEN environment variable
resource "coder_env" "supabase_access_token" {
  count    = local.access_token != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "SUPABASE_ACCESS_TOKEN"
  value    = local.access_token
}

# Set SUPABASE_DB_PASSWORD environment variable (optional)
resource "coder_env" "supabase_db_password" {
  count    = var.db_password != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "SUPABASE_DB_PASSWORD"
  value    = var.db_password
}

output "scripts" {
  description = "Ordered list of coder exp sync names produced by this module."
  value       = module.coder_utils.scripts
}

output "access_token" {
  description = "The Supabase access token (from external auth or direct variable)."
  value       = local.access_token
  sensitive   = true
}

output "module_directory" {
  description = "The directory where Supabase CLI and logs are stored."
  value       = local.module_dir
}
