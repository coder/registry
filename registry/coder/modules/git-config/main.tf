terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.23"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "allow_username_change" {
  type        = bool
  description = "Allow developers to change their git username."
  default     = true
}

variable "allow_email_change" {
  type        = bool
  description = "Allow developers to change their git email."
  default     = false
}

variable "coder_parameter_order" {
  type        = number
  description = "The order determines the position of a template parameter in the UI/CLI presentation. The lowest order is shown first and parameters with equal order are sorted by name (ascending order)."
  default     = null
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_parameter" "user_email" {
  count        = var.allow_email_change ? 1 : 0
  name         = "user_email"
  type         = "string"
  default      = ""
  order        = var.coder_parameter_order != null ? var.coder_parameter_order + 0 : null
  description  = "Git user.email to be used for commits. Leave empty to default to Coder user's email."
  display_name = "Git config user.email"
  mutable      = true
}

data "coder_parameter" "username" {
  count        = var.allow_username_change ? 1 : 0
  name         = "username"
  type         = "string"
  default      = ""
  order        = var.coder_parameter_order != null ? var.coder_parameter_order + 1 : null
  description  = "Git user.name to be used for commits. Leave empty to default to Coder user's Full Name."
  display_name = "Full Name for Git config"
  mutable      = true
}

resource "coder_env" "git_author_name" {
  agent_id = var.agent_id
  name     = "GIT_AUTHOR_NAME"
  value    = coalesce(try(data.coder_parameter.username[0].value, ""), data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
}

resource "coder_env" "git_commmiter_name" {
  agent_id = var.agent_id
  name     = "GIT_COMMITTER_NAME"
  value    = coalesce(try(data.coder_parameter.username[0].value, ""), data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
}

resource "coder_env" "git_author_email" {
  agent_id = var.agent_id
  name     = "GIT_AUTHOR_EMAIL"
  value    = coalesce(try(data.coder_parameter.user_email[0].value, ""), data.coder_workspace_owner.me.email)
  count    = data.coder_workspace_owner.me.email != "" ? 1 : 0
}

resource "coder_env" "git_commmiter_email" {
  agent_id = var.agent_id
  name     = "GIT_COMMITTER_EMAIL"
  value    = coalesce(try(data.coder_parameter.user_email[0].value, ""), data.coder_workspace_owner.me.email)
  count    = data.coder_workspace_owner.me.email != "" ? 1 : 0
}
