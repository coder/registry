terraform {
  required_version = ">= 1.0"

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

variable "port" {
  type        = number
  description = "The port to run VS Code Web on."
  default     = 13338
}

variable "display_name" {
  type        = string
  description = "The display name for the VS Code Web application."
  default     = "VS Code Web"
}

variable "slug" {
  type        = string
  description = "The slug for the VS Code Web application."
  default     = "vscode-web"
}

variable "folder" {
  type        = string
  description = "The folder to open in vscode-web."
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

variable "log_path" {
  type        = string
  description = "The path to log."
  default     = "/tmp/vscode-web.log"
}

variable "install_prefix" {
  type        = string
  description = "The prefix to install vscode-web to."
  default     = "/tmp/vscode-web"
}

variable "commit_id" {
  type        = string
  description = "Specify the commit ID of the VS Code Web binary to pin to a specific version. If left empty, the latest stable version is used."
  default     = ""
}

variable "extensions" {
  type        = list(string)
  description = "A list of extensions to install."
  default     = []
}

variable "accept_license" {
  type        = bool
  description = "Accept the VS Code Server license. https://code.visualstudio.com/license/server"
  default     = false
  validation {
    condition     = var.accept_license == true
    error_message = "You must accept the VS Code license agreement by setting accept_license=true."
  }
}

variable "telemetry_level" {
  type        = string
  description = "Set the telemetry level for VS Code Web."
  default     = "error"
  validation {
    condition     = var.telemetry_level == "off" || var.telemetry_level == "crash" || var.telemetry_level == "error" || var.telemetry_level == "all"
    error_message = "Incorrect value. Please set either 'off', 'crash', 'error', or 'all'."
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

variable "settings" {
  type        = any
  description = "A map of settings to apply to VS Code web."
  default     = {}
}

variable "offline" {
  type        = bool
  description = "Just run VS Code Web in the background, don't fetch it from the internet."
  default     = false
}

variable "use_cached" {
  type        = bool
  description = "Uses cached copy of VS Code Web in the background, otherwise fetches it from internet."
  default     = false
}

variable "disable_trust" {
  type        = bool
  description = "Disables workspace trust protection for VS Code Web."
  default     = false
}

variable "extensions_dir" {
  type        = string
  description = "Override the directory to store extensions in."
  default     = ""
}

variable "auto_install_extensions" {
  type        = bool
  description = "Automatically install recommended extensions when VS Code Web starts."
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

variable "platform" {
  type        = string
  description = "The platform to use for the VS Code Web."
  default     = ""
  validation {
    condition     = var.platform == "" || var.platform == "linux" || var.platform == "darwin" || var.platform == "alpine" || var.platform == "win32"
    error_message = "Incorrect value. Please set either 'linux', 'darwin', or 'alpine' or 'win32'."
  }
}

variable "workspace" {
  type        = string
  description = "Path to a .code-workspace file to open in vscode-web."
  default     = null
}

data "coder_workspace_owner" "me" {}
data "coder_workspace" "me" {}

resource "coder_script" "vscode-web" {
  agent_id     = var.agent_id
  display_name = "VS Code Web"
  icon         = "/icon/code.svg"
  script = templatefile("${path.module}/run.sh", {
    PORT : var.port,
    LOG_PATH : var.log_path,
    INSTALL_PREFIX : var.install_prefix,
    EXTENSIONS : join(",", var.extensions),
    TELEMETRY_LEVEL : var.telemetry_level,
    // This is necessary otherwise the quotes are stripped!
    SETTINGS : replace(jsonencode(var.settings), "\"", "\\\""),
    OFFLINE : var.offline,
    USE_CACHED : var.use_cached,
    DISABLE_TRUST : var.disable_trust,
    EXTENSIONS_DIR : var.extensions_dir,
    FOLDER : var.folder,
    WORKSPACE : var.workspace,
    AUTO_INSTALL_EXTENSIONS : var.auto_install_extensions,
    SERVER_BASE_PATH : local.server_base_path,
    COMMIT_ID : var.commit_id,
    PLATFORM : var.platform,
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

    precondition {
      condition     = (var.workspace == "" || var.folder == "")
      error_message = "Set only one of `workspace` or `folder`."
    }
  }
}

resource "coder_app" "vscode-web" {
  agent_id     = var.agent_id
  slug         = var.slug
  display_name = var.display_name
  url          = local.url
  icon         = "/icon/code.svg"
  subdomain    = var.subdomain
  share        = var.share
  order        = var.order
  group        = var.group

  healthcheck {
    url       = local.healthcheck_url
    interval  = 5
    threshold = 6
  }
}

locals {
  server_base_path = var.subdomain ? "" : format("/@%s/%s/apps/%s/", data.coder_workspace_owner.me.name, data.coder_workspace.me.name, var.slug)
  url = (
    var.workspace != "" ?
    "http://localhost:${var.port}${local.server_base_path}?workspace=${urlencode(var.workspace)}" :
    var.folder != "" ?
    "http://localhost:${var.port}${local.server_base_path}?folder=${urlencode(var.folder)}" :
    "http://localhost:${var.port}${local.server_base_path}"
  )
  healthcheck_url = var.subdomain ? "http://localhost:${var.port}/healthz" : "http://localhost:${var.port}${local.server_base_path}/healthz"
}
