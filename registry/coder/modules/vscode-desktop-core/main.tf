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

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_app" "vscode-desktop" {
  agent_id = var.agent_id
  external = true

  icon         = var.coder_app_icon
  slug         = var.coder_app_slug
  display_name = var.coder_app_display_name

  order = var.coder_app_order
  group = var.coder_app_group

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