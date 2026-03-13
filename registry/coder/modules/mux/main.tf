terraform {
  # Requires Terraform 1.9+ for cross-variable validation references
  required_version = ">= 1.9"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "port" {
  type        = number
  description = "The port to run Mux on."
  default     = 4000
}

variable "display_name" {
  type        = string
  description = "The display name for the Mux application."
  default     = "Mux"
}

variable "slug" {
  type        = string
  description = "The slug for the Mux application."
  default     = "mux"
}

variable "install_prefix" {
  type        = string
  description = "The prefix to install Mux to."
  default     = "/tmp/mux"
}

variable "log_path" {
  type        = string
  description = "The path for Mux logs."
  default     = "/tmp/mux.log"
}

variable "restart_on_kill" {
  type        = bool
  description = "Restart Mux after it exits by waiting briefly, removing the server lock, and launching it again."
  default     = false
}

variable "restart_delay_seconds" {
  type        = number
  description = "How long to wait before restarting Mux after it exits when restart_on_kill is enabled."
  default     = 5

  validation {
    condition     = var.restart_delay_seconds >= 0
    error_message = "The 'restart_delay_seconds' variable must be greater than or equal to 0."
  }
}

variable "max_restart_attempts" {
  type        = number
  description = "Maximum whole-number restart attempts before giving up. Set to 0 for unlimited restarts when restart_on_kill is enabled."
  default     = 0

  validation {
    condition     = var.max_restart_attempts >= 0 && floor(var.max_restart_attempts) == var.max_restart_attempts
    error_message = "The 'max_restart_attempts' variable must be a whole number greater than or equal to 0."
  }
}

variable "add_project" {
  type        = string
  description = "Optional path to add/open as a project in Mux on startup."
  default     = null
}

variable "additional_arguments" {
  type        = string
  description = "Additional command-line arguments to pass to `mux server` (for example: `--add-project /path --open-mode pinned`)."
  default     = ""
}

variable "install_version" {
  type        = string
  description = "The version or dist-tag of Mux to install."
  default     = "next"
}

variable "package_manager" {
  type        = string
  description = "Package manager to install Mux. 'auto' detects npm, pnpm, or bun (falling back to tarball download). Set to 'npm', 'pnpm', or 'bun' to force a specific one."
  default     = "auto"
  validation {
    condition     = contains(["auto", "npm", "pnpm", "bun"], var.package_manager)
    error_message = "The 'package_manager' variable must be one of: 'auto', 'npm', 'pnpm', 'bun'."
  }
}

variable "registry_url" {
  type        = string
  description = "The npm-compatible registry URL to install Mux from. Override this for private registries or mirrors."
  default     = "https://registry.npmjs.org"
}


variable "share" {
  type    = string
  default = "owner"
  validation {
    condition     = var.share == "owner" || var.share == "authenticated" || var.share == "public"
    error_message = "Incorrect value. Please set either 'owner', 'authenticated', or 'public'."
  }
}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  default     = null
}

variable "group" {
  type        = string
  description = "The name of a group that this app belongs to."
  default     = null
}

variable "install" {
  type        = bool
  description = "Install Mux from the network (npm or tarball). If false, run without installing (requires a pre-installed Mux)."
  default     = true
}

variable "use_cached" {
  type        = bool
  description = "Use cached copy of Mux if present; otherwise install from npm"
  default     = false
}

variable "subdomain" {
  type        = bool
  description = <<-EOT
    Determines whether the app will be accessed via it's own subdomain or whether it will be accessed via a path on Coder.
    If wildcards have not been setup by the administrator then apps with "subdomain" set to true will not be accessible.
  EOT
  default     = true
}

variable "open_in" {
  type        = string
  description = <<-EOT
    Determines where the app will be opened. Valid values are `"tab"` and `"slim-window" (default)`.
    `"tab"` opens in a new tab in the same browser window.
    `"slim-window"` opens a new browser window without navigation controls.
  EOT
  default     = "slim-window"
  validation {
    condition     = contains(["tab", "slim-window"], var.open_in)
    error_message = "The 'open_in' variable must be one of: 'tab', 'slim-window'."
  }
}

# Per-module auth token for cross-site request protection.
# We pass this token into each mux process at launch time (process-scoped env)
# and include it in the app URL query string (?token=...).
#
# Why process-scoped env instead of a shared coder_env value:
# multiple mux module instances can target the same agent (different slug/port).
# A single global MUX_SERVER_AUTH_TOKEN env key would cause collisions.
resource "random_password" "mux_auth_token" {
  length  = 64
  special = false
}

locals {
  mux_auth_token = random_password.mux_auth_token.result
  registry_url   = trimsuffix(var.registry_url, "/")
}

resource "coder_script" "mux" {
  agent_id     = var.agent_id
  display_name = var.display_name
  icon         = "/icon/mux.svg"
  script = templatefile("${path.module}/run.sh", {
    VERSION : var.install_version,
    PORT : var.port,
    LOG_PATH : var.log_path,
    ADD_PROJECT : var.add_project == null ? "" : var.add_project,
    ADDITIONAL_ARGUMENTS : var.additional_arguments,
    INSTALL_PREFIX : var.install_prefix,
    OFFLINE : !var.install,
    USE_CACHED : var.use_cached,
    AUTH_TOKEN : local.mux_auth_token,
    RESTART_ON_KILL : var.restart_on_kill,
    RESTART_DELAY_SECONDS : var.restart_delay_seconds,
    MAX_RESTART_ATTEMPTS : var.max_restart_attempts,
    PACKAGE_MANAGER : var.package_manager,
    REGISTRY_URL : local.registry_url,
  })
  run_on_start = true

  lifecycle {
    precondition {
      condition     = var.install || !var.use_cached
      error_message = "Cannot use 'use_cached' when 'install' is false"
    }
  }
}

resource "coder_app" "mux" {
  agent_id     = var.agent_id
  slug         = var.slug
  display_name = var.display_name
  url          = "http://localhost:${var.port}?token=${local.mux_auth_token}"
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
