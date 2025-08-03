terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.23"
    }
  }
}

variable "jfrog_url" {
  type        = string
  description = "JFrog instance URL. e.g. https://myartifactory.jfrog.io"
  validation {
    condition     = can(regex("^(https|http)://", var.jfrog_url))
    error_message = "jfrog_url must be a valid URL starting with either 'https://' or 'http://'"
  }
}

variable "jfrog_server_id" {
  type        = string
  description = "The server ID of the JFrog instance for JFrog CLI configuration"
  default     = "0"
}

variable "username_field" {
  type        = string
  description = "The field to use for the artifactory username. i.e. Coder username or email."
  default     = "username"
  validation {
    condition     = can(regex("^(email|username)$", var.username_field))
    error_message = "username_field must be either 'email' or 'username'"
  }
}

variable "external_auth_id" {
  type        = string
  description = "JFrog external auth ID. Default: 'jfrog'"
  default     = "jfrog"
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "maven_repositories" {
  type        = list(string)
  description = "List of Maven repository keys to configure. e.g. ['maven-local', 'maven-remote', 'maven-virtual']"
  default     = []
}

variable "configure_code_server" {
  type        = bool
  description = "Set to true to configure code-server to use JFrog."
  default     = false
}

locals {
  # The username field to use for artifactory
  username   = var.username_field == "email" ? data.coder_workspace_owner.me.email : data.coder_workspace_owner.me.name
  jfrog_host = split("://", var.jfrog_url)[1]
  common_values = {
    JFROG_URL                = var.jfrog_url
    JFROG_HOST               = local.jfrog_host
    JFROG_SERVER_ID          = var.jfrog_server_id
    ARTIFACTORY_USERNAME     = local.username
    ARTIFACTORY_EMAIL        = data.coder_workspace_owner.me.email
    ARTIFACTORY_ACCESS_TOKEN = data.coder_external_auth.jfrog.access_token
  }
  maven_settings = templatefile(
    "${path.module}/settings.xml.tftpl", merge(local.common_values, { REPOS = var.maven_repositories })
  )
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_external_auth" "jfrog" {
  id = var.external_auth_id
}

resource "coder_script" "jfrog_maven" {
  agent_id     = var.agent_id
  display_name = "jfrog-maven"
  icon         = "/icon/jfrog.svg"
  script = templatefile("${path.module}/run.sh", merge(
    local.common_values,
    {
      CONFIGURE_CODE_SERVER = var.configure_code_server
      HAS_MAVEN             = length(var.maven_repositories) == 0 ? "" : "YES"
      MAVEN_SETTINGS        = local.maven_settings
      REPOSITORY_MAVEN      = try(element(var.maven_repositories, 0), "")
    }
  ))
  run_on_start = true
}

resource "coder_env" "jfrog_ide_url" {
  count    = var.configure_code_server ? 1 : 0
  agent_id = var.agent_id
  name     = "JFROG_IDE_URL"
  value    = var.jfrog_url
}

resource "coder_env" "jfrog_ide_access_token" {
  count    = var.configure_code_server ? 1 : 0
  agent_id = var.agent_id
  name     = "JFROG_IDE_ACCESS_TOKEN"
  value    = data.coder_external_auth.jfrog.access_token
}

resource "coder_env" "jfrog_ide_store_connection" {
  count    = var.configure_code_server ? 1 : 0
  agent_id = var.agent_id
  name     = "JFROG_IDE_STORE_CONNECTION"
  value    = true
}

output "access_token" {
  description = "value of the JFrog access token"
  value       = data.coder_external_auth.jfrog.access_token
  sensitive   = true
}

output "username" {
  description = "value of the JFrog username"
  value       = local.username
} 