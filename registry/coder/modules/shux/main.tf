terraform {
  # Requires Terraform 1.9+ for cross-variable validation references
  required_version = ">= 1.9"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

variable "agent_id" {
  description = "The ID of a Coder agent."
  type        = string
}

variable "port" {
  description = "The port to run Shux on."
  type        = number
  default     = 4000
}

variable "display_name" {
  description = "The display name for the Shux application."
  type        = string
  default     = "Shux"
}

variable "slug" {
  description = "The slug for the Shux application."
  type        = string
  default     = "shux"
}

variable "install_prefix" {
  description = "The prefix to install Shux to."
  type        = string
  default     = "$HOME/.coder-modules/coder/shux/install"
}

variable "log_path" {
  description = "The path for Shux server logs."
  type        = string
  default     = "$HOME/.coder-modules/coder/shux/logs/shux.log"
}

variable "restart_on_kill" {
  description = "Restart Shux after it exits by waiting briefly, removing the server lock, and launching it again."
  type        = bool
  default     = false
}

variable "restart_delay_seconds" {
  description = "How long to wait before restarting Shux after it exits when restart_on_kill is enabled."
  type        = number
  default     = 5

  validation {
    condition     = var.restart_delay_seconds >= 0
    error_message = "The 'restart_delay_seconds' variable must be greater than or equal to 0."
  }
}

variable "max_restart_attempts" {
  description = "Maximum whole-number restart attempts before giving up. Set to 0 for unlimited restarts when restart_on_kill is enabled."
  type        = number
  default     = 0

  validation {
    condition     = var.max_restart_attempts >= 0 && floor(var.max_restart_attempts) == var.max_restart_attempts
    error_message = "The 'max_restart_attempts' variable must be a whole number greater than or equal to 0."
  }
}

variable "add_project" {
  description = "Optional path to add/open as a project in Shux on startup."
  type        = string
  default     = null
}

variable "additional_arguments" {
  description = "Additional command-line arguments to pass to `shux server` (for example: `--add-project /path --open-mode pinned`)."
  type        = string
  default     = ""
}

variable "install_version" {
  description = "The version or dist-tag of the @coder/shux npm package to install."
  type        = string
  default     = "next"
}

variable "package_manager" {
  description = "Package manager to install Shux. 'auto' detects npm, pnpm, or bun (falling back to tarball download). Set to 'npm', 'pnpm', or 'bun' to force a specific one."
  type        = string
  default     = "auto"

  validation {
    condition     = contains(["auto", "npm", "pnpm", "bun"], var.package_manager)
    error_message = "The 'package_manager' variable must be one of: 'auto', 'npm', 'pnpm', 'bun'."
  }
}

variable "registry_url" {
  description = "The npm-compatible registry URL to install Shux from. Override this for private registries or mirrors."
  type        = string
  default     = "https://registry.npmjs.org"
}

variable "share" {
  description = "The sharing level of the Shux application."
  type        = string
  default     = "owner"

  validation {
    condition     = var.share == "owner" || var.share == "authenticated" || var.share == "public"
    error_message = "Incorrect value. Please set either 'owner', 'authenticated', or 'public'."
  }
}

variable "order" {
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  type        = number
  default     = null
}

variable "group" {
  description = "The name of a group that this app belongs to."
  type        = string
  default     = null
}

variable "install" {
  description = "Install Shux from the network (npm or tarball). If false, run without installing (requires a pre-installed Shux)."
  type        = bool
  default     = true
}

variable "use_cached" {
  description = "Use cached copy of Shux if present; otherwise install from the registry."
  type        = bool
  default     = false

  validation {
    condition     = var.install || !var.use_cached
    error_message = "Cannot use 'use_cached' when 'install' is false."
  }
}

variable "subdomain" {
  description = <<-EOT
    Determines whether the app will be accessed via it's own subdomain or whether it will be accessed via a path on Coder.
    If wildcards have not been setup by the administrator then apps with "subdomain" set to true will not be accessible.
  EOT
  type        = bool
  default     = true
}

variable "open_in" {
  description = <<-EOT
    Determines where the app will be opened. Valid values are `"tab"` and `"slim-window" (default)`.
    `"tab"` opens in a new tab in the same browser window.
    `"slim-window"` opens a new browser window without navigation controls.
  EOT
  type        = string
  default     = "slim-window"

  validation {
    condition     = contains(["tab", "slim-window"], var.open_in)
    error_message = "The 'open_in' variable must be one of: 'tab', 'slim-window'."
  }
}

variable "pre_install_script" {
  description = "Custom script to run before installing Shux."
  type        = string
  default     = null
}

variable "post_install_script" {
  description = "Custom script to run after installing Shux."
  type        = string
  default     = null
}

# Per-module auth token for cross-site request protection.
# We pass this token into each shux process at launch time (process-scoped env)
# and include it in the app URL query string (?token=...).
#
# Why process-scoped env instead of a shared coder_env value:
# multiple shux module instances can target the same agent (different slug/port).
# A single global SHUX_SERVER_AUTH_TOKEN env key would cause collisions.
resource "random_password" "shux_auth_token" {
  length  = 64
  special = false
}

locals {
  shux_auth_token = random_password.shux_auth_token.result
  registry_url    = trimsuffix(var.registry_url, "/")

  # ensure_node is shared verbatim by the install and start scripts, which run
  # as separate coder_script processes and cannot share exported PATH state.
  ensure_node = file("${path.module}/scripts/ensure_node.sh")

  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ENSURE_NODE     = local.ensure_node
    VERSION         = var.install_version
    INSTALL_PREFIX  = var.install_prefix
    OFFLINE         = !var.install
    USE_CACHED      = var.use_cached
    PACKAGE_MANAGER = var.package_manager
    REGISTRY_URL    = local.registry_url
  })

  start_script = templatefile("${path.module}/scripts/start.sh.tftpl", {
    ENSURE_NODE           = local.ensure_node
    PORT                  = var.port
    LOG_PATH              = var.log_path
    ADD_PROJECT           = var.add_project == null ? "" : var.add_project
    ADDITIONAL_ARGUMENTS  = var.additional_arguments
    INSTALL_PREFIX        = var.install_prefix
    AUTH_TOKEN            = local.shux_auth_token
    RESTART_ON_KILL       = var.restart_on_kill
    RESTART_DELAY_SECONDS = var.restart_delay_seconds
    MAX_RESTART_ATTEMPTS  = var.max_restart_attempts
  })
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/.coder-modules/coder/shux"
  display_name_prefix = var.display_name
  # Coder deployments do not ship /icon/shux.svg yet; the Mux icon is the
  # closest available built-in.
  icon                = "/icon/mux.svg"
  pre_install_script  = var.pre_install_script
  install_script      = local.install_script
  post_install_script = var.post_install_script
  start_script        = local.start_script
}

resource "coder_app" "shux" {
  agent_id     = var.agent_id
  slug         = var.slug
  display_name = var.display_name
  url          = "http://localhost:${var.port}?token=${local.shux_auth_token}"
  icon         = "/icon/mux.svg"
  subdomain    = var.subdomain
  share        = var.share
  order        = var.order
  group        = var.group
  open_in      = var.open_in

  healthcheck {
    url       = "http://localhost:${var.port}/health"
    interval  = 5
    threshold = 6
  }
}

output "scripts" {
  description = "Ordered list of coder exp sync names produced by this module, in run order."
  # The start script embeds the sensitive auth token, which taints every
  # coder-utils output. The sync names themselves carry no secret material.
  value = nonsensitive(module.coder_utils.scripts)
}
