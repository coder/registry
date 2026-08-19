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
  type        = string
  description = "The ID of a Coder agent."
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

variable "icon" {
  type        = string
  description = "The icon to use for the Supabase app."
  default     = "/icon/supabase.svg"
}

variable "external_auth_id" {
  type        = string
  description = "Supabase external auth provider ID configured in Coder."
  default     = "supabase"
}

variable "use_external_auth" {
  type        = bool
  description = "Use Coder external auth for Supabase authentication. Note: The Supabase CLI may reject OAuth tokens due to format validation; if so, set to false and use a Personal Access Token via the access_token variable."
  default     = false
}

variable "access_token" {
  type        = string
  description = "Supabase personal access token. Only used when use_external_auth is false."
  default     = ""
  sensitive   = true
}

variable "install_method" {
  type        = string
  description = "How to install the Supabase CLI. 'detect' automatically selects the best available method (brew → scoop → native package → binary). Use 'brew', 'scoop', or 'binary' to force a specific method."
  default     = "detect"
  validation {
    condition     = contains(["detect", "brew", "scoop", "binary"], var.install_method)
    error_message = "The 'install_method' variable must be one of: 'detect', 'brew', 'scoop', 'binary'."
  }
}

variable "supabase_version" {
  type        = string
  description = "The version of Supabase CLI to install. Use 'latest' for the most recent release."
  default     = "latest"
}

variable "db_password" {
  type        = string
  description = "Remote Postgres database password for non-interactive CLI commands like 'supabase link' (optional). Sets SUPABASE_DB_PASSWORD environment variable."
  default     = ""
  sensitive   = true
}

variable "project_ref" {
  type        = string
  description = "Supabase project reference (e.g., 'abcdefghijklmnop'). When set, links the CLI to this project and adds a dashboard link."
  default     = ""
}

variable "project_dir" {
  type        = string
  description = "Directory to link the Supabase project in. Created if it doesn't exist. Defaults to $HOME if empty."
  default     = ""
}

variable "dashboard_app" {
  type        = bool
  description = "Whether to create the Supabase dashboard workspace app."
  default     = true
}


variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Supabase CLI. Can be used for dependency ordering between modules."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Supabase CLI."
  default     = null
}

# External auth data source - only used when use_external_auth is true
data "coder_external_auth" "supabase" {
  count = var.use_external_auth ? 1 : 0
  id    = var.external_auth_id
}

locals {
  module_dir_name = ".coder-modules/coder/supabase"

  # Determine the access token to use
  access_token = var.use_external_auth ? try(data.coder_external_auth.supabase[0].access_token, "") : var.access_token

  # Render the install script
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL_METHOD = var.install_method
    ARG_VERSION        = var.supabase_version
    ARG_PROJECT_REF    = var.project_ref
    ARG_PROJECT_DIR    = var.project_dir
  })
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/${local.module_dir_name}"
  display_name_prefix = "Supabase"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  install_script      = local.install_script
  post_install_script = var.post_install_script
}

resource "coder_env" "supabase_access_token" {
  count    = local.access_token != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "SUPABASE_ACCESS_TOKEN"
  value    = local.access_token
}

resource "coder_env" "supabase_db_password" {
  count    = var.db_password != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "SUPABASE_DB_PASSWORD"
  value    = var.db_password
}

resource "coder_app" "supabase" {
  count        = var.dashboard_app ? 1 : 0
  agent_id     = var.agent_id
  slug         = "supabase"
  display_name = "Supabase"
  icon         = var.icon
  url          = var.project_ref != "" ? "https://supabase.com/dashboard/project/${var.project_ref}" : "https://supabase.com/dashboard"
  external     = true
}


# Pass-through of coder-utils script outputs so upstream modules can serialize
# their coder_script resources behind this module's install pipeline using
# `coder exp sync want <self> <each name>`.
output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module creates, in run order (pre_install, install, post_install). Scripts that were not configured are absent from the list."
  value       = module.coder_utils.scripts
}

output "access_token" {
  description = "The Supabase access token (from external auth or direct variable)."
  value       = local.access_token
  sensitive   = true
}

output "module_directory" {
  description = "The directory where Supabase CLI logs and scripts are stored."
  value       = "$HOME/${local.module_dir_name}"
}
