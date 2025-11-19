terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
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

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "description" {
  type        = string
  description = "A custom description for the dotfiles parameter. This is shown in the UI - and allows you to customize the instructions you give to your users."
  default     = "Enter a URL for a [dotfiles repository](https://dotfiles.github.io) to personalize your workspace"
}

variable "default_dotfiles_uri" {
  type        = string
  description = "The default dotfiles URI if the workspace user does not provide one"
  default     = ""
}

variable "default_dotfiles_branch" {
  type        = string
  description = "The default dotfiles branch if the workspace user does not provide one"
  default     = "main"
}

variable "dotfiles_uri" {
  type        = string
  description = "The URL to a dotfiles repository. (optional, when set, the user isn't prompted for their dotfiles)"

  default = null
}

variable "dotfiles_branch" {
  type        = string
  description = "The branch to use for the dotfiles repository (optional, when set, the user isn't prompted for the branch)"
  default     = null
}

variable "user" {
  type        = string
  description = "The name of the user to apply the dotfiles to. (optional, applies to the current user by default)"
  default     = null
}

variable "coder_parameter_order" {
  type        = number
  description = "The order determines the position of a template parameter in the UI/CLI presentation. The lowest order is shown first and parameters with equal order are sorted by name (ascending order)."
  default     = null
}

variable "manual_update" {
  type        = bool
  description = "If true, this adds a button to workspace page to refresh dotfiles on demand."
  default     = false
}

data "coder_parameter" "dotfiles_uri" {
  count        = var.dotfiles_uri == null ? 1 : 0
  type         = "string"
  name         = "dotfiles_uri"
  display_name = "Dotfiles URL"
  order        = var.coder_parameter_order
  default      = var.default_dotfiles_uri
  description  = var.description
  mutable      = true
  icon         = "/icon/dotfiles.svg"
}

data "coder_parameter" "dotfiles_branch" {
  count        = var.dotfiles_branch == null ? 1 : 0
  type         = "string"
  name         = "dotfiles_branch"
  display_name = "Dotfiles Branch"
  default      = var.default_dotfiles_branch
  description  = "The branch to use for the dotfiles repository"
  mutable      = true
  icon         = "/icon/dotfiles.svg"
}

locals {
  dotfiles_uri    = var.dotfiles_uri != null ? var.dotfiles_uri : data.coder_parameter.dotfiles_uri[0].value
  dotfiles_branch = var.dotfiles_branch != null ? var.dotfiles_branch : data.coder_parameter.dotfiles_branch[0].value
  user            = var.user != null ? var.user : ""
}

resource "coder_script" "dotfiles" {
  agent_id = var.agent_id
  script = templatefile("${path.module}/run.sh", {
    DOTFILES_URI : local.dotfiles_uri,
    DOTFILES_USER : local.user,
    DOTFILES_BRANCH : local.dotfiles_branch
  })
  display_name = "Dotfiles"
  icon         = "/icon/dotfiles.svg"
  run_on_start = true
}

resource "coder_app" "dotfiles" {
  count        = var.manual_update ? 1 : 0
  agent_id     = var.agent_id
  display_name = "Refresh Dotfiles"
  slug         = "dotfiles"
  icon         = "/icon/dotfiles.svg"
  order        = var.order
  group        = var.group
  command = templatefile("${path.module}/run.sh", {
    DOTFILES_URI : local.dotfiles_uri,
    DOTFILES_USER : local.user,
    DOTFILES_BRANCH : local.dotfiles_branch
  })
}

output "dotfiles_uri" {
  description = "Dotfiles URI"
  value       = local.dotfiles_uri
}
