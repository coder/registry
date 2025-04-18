terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.17"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "extensions" {
  type        = list(string)
  description = "A list of extensions to install."
  default     = []
}

variable "port" {
  type        = number
  description = "The port to run code-server on."
  default     = 13337
}

variable "display_name" {
  type        = string
  description = "The display name for the code-server application."
  default     = "code-server"
}

variable "slug" {
  type        = string
  description = "The slug for the code-server application."
  default     = "code-server"
}

variable "settings" {
  type        = any
  description = "A map of settings to apply to code-server."
  default     = {}
}

variable "folder" {
  type        = string
  description = "The folder to open in code-server."
  default     = ""
}

variable "install_prefix" {
  type        = string
  description = "The prefix to install code-server to."
  default     = "/tmp/code-server"
}

variable "log_path" {
  type        = string
  description = "The path to log code-server to."
  default     = "/tmp/code-server.log"
}

variable "install_version" {
  type        = string
  description = "The version of code-server to install."
  default     = ""
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

variable "offline" {
  type        = bool
  description = "Just run code-server in the background, don't fetch it from GitHub"
  default     = false
}

variable "use_cached" {
  type        = bool
  description = "Uses cached copy code-server in the background, otherwise fetched it from GitHub"
  default     = false
}

variable "use_cached_extensions" {
  type        = bool
  description = "Uses cached copy of extensions, otherwise do a forced upgrade"
  default     = false
}

variable "extensions_dir" {
  type        = string
  description = "Override the directory to store extensions in."
  default     = ""
}

variable "auto_install_extensions" {
  type        = bool
  description = "Automatically install recommended extensions when code-server starts."
  default     = false
}

variable "subdomain" {
  type        = bool
  description = <<-EOT
    Determines whether the app will be accessed via it's own subdomain or whether it will be accessed via a path on Coder.
    If wildcards have not been setup by the administrator then apps with "subdomain" set to true will not be accessible.
  EOT
  default     = false
}

resource "coder_script" "code-server" {
  agent_id     = var.agent_id
  display_name = "code-server"
  icon         = "/icon/code.svg"
  script = templatefile("${path.module}/run.sh", {
    VERSION : var.install_version,
    EXTENSIONS : join(",", var.extensions),
    APP_NAME : var.display_name,
    PORT : var.port,
    LOG_PATH : var.log_path,
    INSTALL_PREFIX : var.install_prefix,
    // This is necessary otherwise the quotes are stripped!
    SETTINGS : replace(jsonencode(var.settings), "\"", "\\\""),
    OFFLINE : var.offline,
    USE_CACHED : var.use_cached,
    USE_CACHED_EXTENSIONS : var.use_cached_extensions,
    EXTENSIONS_DIR : var.extensions_dir,
    FOLDER : var.folder,
    AUTO_INSTALL_EXTENSIONS : var.auto_install_extensions,
  })
  run_on_start = true

  lifecycle {
    precondition {
      condition     = !var.offline || length(var.extensions) == 0
      error_message = "Offline mode does not allow extensions to be installed"
    }

    precondition {
      condition     = !var.offline || !var.use_cached
      error_message = "Offline and Use Cached can not be used together"
    }
  }
}

resource "coder_app" "code-server" {
  agent_id     = var.agent_id
  slug         = var.slug
  display_name = var.display_name
  url          = "http://localhost:${var.port}/${var.folder != "" ? "?folder=${urlencode(var.folder)}" : ""}"
  icon         = "/icon/code.svg"
  subdomain    = var.subdomain
  share        = var.share
  order        = var.order

  healthcheck {
    url       = "http://localhost:${var.port}/healthz"
    interval  = 5
    threshold = 6
  }
}
