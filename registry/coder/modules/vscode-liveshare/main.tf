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
  description = "The ID of the Coder agent to attach the button to."
  type        = string
}

variable "folder" {
  description = "The absolute workspace folder to open and share with Live Share."
  type        = string

  validation {
    condition     = startswith(var.folder, "/") && length(regexall("[\\r\\n]", var.folder)) == 0
    error_message = "folder must be an absolute path without line breaks."
  }
}

variable "agent_name" {
  description = "The agent to connect to. When omitted, the Coder extension asks if the workspace has multiple agents."
  type        = string
  default     = null

  validation {
    condition     = var.agent_name == null ? true : trimspace(var.agent_name) != ""
    error_message = "agent_name must not be empty when provided."
  }
}

variable "order" {
  description = "The position of the button in the workspace UI."
  type        = number
  default     = null
}

variable "group" {
  description = "The group that this app belongs to."
  type        = string
  default     = null
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_app" "liveshare" {
  agent_id     = var.agent_id
  slug         = "vscode-liveshare"
  display_name = "Open Liveshare"
  icon         = "/icon/code.svg"
  external     = true
  order        = var.order
  group        = var.group

  url = join("", [
    "vscode://coder.coder-remote/open?liveShare=true",
    "&owner=", urlencode(data.coder_workspace_owner.me.name),
    "&workspace=", urlencode(data.coder_workspace.me.name),
    "&folder=", urlencode(var.folder),
    var.agent_name != null ? "&agent=${urlencode(var.agent_name)}" : "",
    "&url=", urlencode(data.coder_workspace.me.access_url),
    "&token=$SESSION_TOKEN",
  ])
}

output "vscode_url" {
  description = "URL that opens the selected workspace folder and requests a Live Share session."
  value       = coder_app.liveshare.url
}
