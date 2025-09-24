terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.11"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "extensions" {
  type        = list(string)
  description = <<-EOF
    The list of extensions to install in the IDE.
    Example: ["ms-python.python", "ms-vscode.cpptools"]
    EOF
  default     = []
}

variable "extensions_urls" {
  type        = list(string)
  description = <<-EOF
    The list of extension URLs to install in the IDE.
    Example: ["https://marketplace.visualstudio.com/items?itemName=ms-python.python", "https://marketplace.visualstudio.com/items?itemName=ms-vscode.cpptools"]
    EOF
  default     = []
}

variable "extensions_dir" {
  type        = string
  description = "The directory where extensions will be installed."
  default     = ""
}

variable "folder" {
  type        = string
  description = "The folder to open in the IDE."
  default     = ""
}

variable "open_recent" {
  type        = bool
  description = "Open the most recent workspace or folder. Falls back to the folder if there is no recent workspace or folder to open."
  default     = false
}

variable "protocol" {
  type        = string
  description = "The URI protocol for the IDE."
  validation {
    condition     = contains(["vscode", "vscode-insiders", "vscodium", "cursor", "windsurf", "kiro"], var.protocol)
    error_message = "Protocol must be one of: vscode, vscode-insiders, vscodium, cursor, windsurf, or kiro."
  }
}

variable "coder_app_icon" {
  type        = string
  description = "The icon of the coder_app."
}

variable "coder_app_slug" {
  type        = string
  description = "The slug of the coder_app."
}

variable "coder_app_display_name" {
  type        = string
  description = "The display name of the coder_app."
}

variable "coder_app_order" {
  type        = number
  description = "The order of the coder_app."
  default     = null
}

variable "coder_app_group" {
  type        = string
  description = "The group of the coder_app."
  default     = null
}

variable "coder_app_tooltip" {
  type        = string
  description = "An optional tooltip to display on the IDE button."
  default     = null
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  default_extensions_dirs = {
    vscode          = "~/.vscode-server/extensions"
    vscode-insiders = "~/.vscode-server-insiders/extensions"
    vscodium        = "~/.vscode-server-oss/extensions"
    cursor          = "~/.cursor-server/extensions"
    windsurf        = "~/.windsurf-server/extensions"
    kiro            = "~/.kiro-server/extensions"
  }

  # Extensions directory
  final_extensions_dir = var.extensions_dir != "" ? var.extensions_dir : local.default_extensions_dirs[var.protocol]
}

resource "coder_script" "extensions-installer" {
  count        = length(var.extensions) > 0 || length(var.extensions_urls) > 0 ? 1 : 0
  agent_id     = var.agent_id
  display_name = "${var.coder_app_display_name} Extensions"
  icon         = var.coder_app_icon
  script = templatefile("${path.module}/run.sh", {
    EXTENSIONS      = join(",", var.extensions)
    EXTENSIONS_URLS = join(",", var.extensions_urls)
    EXTENSIONS_DIR  = local.final_extensions_dir
    IDE_TYPE        = var.protocol
  })
  run_on_start = true

  lifecycle {
    precondition {
      condition     = !(length(var.extensions) > 0 && length(var.extensions_urls) > 0)
      error_message = "Cannot specify both 'extensions' and 'extensions_urls'. Use 'extensions' for normal operation or 'extensions_urls' for airgapped environments."
    }
  }
}

resource "coder_app" "vscode-desktop" {
  agent_id = var.agent_id
  external = true

  icon         = var.coder_app_icon
  slug         = var.coder_app_slug
  display_name = var.coder_app_display_name
  order        = var.coder_app_order
  group        = var.coder_app_group
  tooltip      = var.coder_app_tooltip

  # While the call to "join" is not strictly necessary, it makes the URL more readable.
  url = join("", [
    "${var.protocol}://coder.coder-remote/open",
    "?owner=${data.coder_workspace_owner.me.name}",
    "&workspace=${data.coder_workspace.me.name}",
    var.folder != "" ? join("", ["&folder=", var.folder]) : "",
    var.open_recent ? "&openRecent" : "",
    "&url=${data.coder_workspace.me.access_url}",
    # NOTE: There is a protocol whitelist for the token replacement, so this will only work with the protocols hardcoded in the front-end.
    # (https://github.com/coder/coder/blob/6ba4b5bbc95e2e528d7f5b1e31fffa200ae1a6db/site/src/modules/apps/apps.ts#L18)
    "&token=$SESSION_TOKEN",
  ])
}

output "ide_uri" {
  value       = coder_app.vscode-desktop.url
  description = "IDE URI."
}
