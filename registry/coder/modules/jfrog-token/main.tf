terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.23"
    }
    artifactory = {
      source  = "registry.terraform.io/jfrog/artifactory"
      version = "~> 10.0.2"
    }
  }
}

variable "jfrog_url" {
  type        = string
  description = "JFrog instance URL. e.g. https://myartifactory.jfrog.io"
  # ensue the URL is HTTPS or HTTP
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

variable "artifactory_access_token" {
  type        = string
  description = "The admin-level access token to use for JFrog."
}

variable "token_description" {
  type        = string
  description = "Free text token description. Useful for filtering and managing tokens."
  default     = "Token for Coder workspace"
}

variable "check_license" {
  type        = bool
  description = "Toggle for pre-flight checking of Artifactory license. Default to `true`."
  default     = true
}

variable "refreshable" {
  type        = bool
  description = "Is this token refreshable? Default is `false`."
  default     = false
}

variable "expires_in" {
  type        = number
  description = "The amount of time, in seconds, it would take for the token to expire."
  default     = null
}

variable "username_field" {
  type        = string
  description = "The field to use for the artifactory username. Default `username`."
  default     = "username"
  validation {
    condition     = can(regex("^(email|username)$", var.username_field))
    error_message = "username_field must be either 'email' or 'username'"
  }
}

variable "username" {
  type        = string
  description = "Username to use for Artifactory. Overrides the field specified in `username_field`"
  default     = null
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "configure_code_server" {
  type        = bool
  description = "Set to true to configure code-server to use JFrog."
  default     = false
}

variable "package_managers" {
  type = object({
    npm    = optional(list(string), [])
    go     = optional(list(string), [])
    pypi   = optional(list(string), [])
    docker = optional(list(string), [])
    conda  = optional(list(string), [])
  })
  description = <<-EOF
    A map of package manager names to their respective artifactory repositories. Unused package managers can be omitted.
    For example:
      {
        npm    = ["GLOBAL_NPM_REPO_KEY", "@SCOPED:NPM_REPO_KEY"]
        go     = ["YOUR_GO_REPO_KEY", "ANOTHER_GO_REPO_KEY"]
        pypi   = ["YOUR_PYPI_REPO_KEY", "ANOTHER_PYPI_REPO_KEY"]
        docker = ["YOUR_DOCKER_REPO_KEY", "ANOTHER_DOCKER_REPO_KEY"]
        conda  = ["YOUR_CONDA_REPO_KEY", "ANOTHER_CONDA_REPO_KEY"]
      }
  EOF
}

locals {
  # The username to use for artifactory
  username   = coalesce(var.username, var.username_field == "email" ? data.coder_workspace_owner.me.email : data.coder_workspace_owner.me.name)
  jfrog_host = split("://", var.jfrog_url)[1]
  common_values = {
    JFROG_URL                = var.jfrog_url
    JFROG_HOST               = local.jfrog_host
    JFROG_SERVER_ID          = var.jfrog_server_id
    ARTIFACTORY_USERNAME     = local.username
    ARTIFACTORY_EMAIL        = data.coder_workspace_owner.me.email
    ARTIFACTORY_ACCESS_TOKEN = artifactory_scoped_token.me.access_token
  }
  npmrc = templatefile(
    "${path.module}/.npmrc.tftpl",
    merge(
      local.common_values,
      {
        REPOS = [
          for r in var.package_managers.npm :
          strcontains(r, ":") ? zipmap(["SCOPE", "NAME"], ["${split(":", r)[0]}:", split(":", r)[1]]) : { SCOPE = "", NAME = r }
        ]
      }
    )
  )
  pip_conf = templatefile(
    "${path.module}/pip.conf.tftpl", merge(local.common_values, { REPOS = var.package_managers.pypi })
  )
  conda_conf = templatefile(
    "${path.module}/conda.conf.tftpl", merge(local.common_values, { REPOS = var.package_managers.conda })
  )
}

# Configure the Artifactory provider
provider "artifactory" {
  url           = join("/", [var.jfrog_url, "artifactory"])
  access_token  = var.artifactory_access_token
  check_license = var.check_license
}

resource "artifactory_scoped_token" "me" {
  # This is hacky, but on terraform plan the data source gives empty strings,
  # which fails validation.
  username    = length(local.username) > 0 ? local.username : "dummy"
  scopes      = ["applied-permissions/user"]
  refreshable = var.refreshable
  expires_in  = var.expires_in
  description = var.token_description
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_script" "jfrog" {
  agent_id     = var.agent_id
  display_name = "jfrog"
  icon         = "/icon/jfrog.svg"
  script = templatefile("${path.module}/run.sh", merge(
    local.common_values,
    {
      CONFIGURE_CODE_SERVER = var.configure_code_server
      HAS_NPM               = length(var.package_managers.npm) == 0 ? "" : "YES"
      NPMRC                 = local.npmrc
      REPOSITORY_NPM        = try(element(var.package_managers.npm, 0), "")
      HAS_GO                = length(var.package_managers.go) == 0 ? "" : "YES"
      REPOSITORY_GO         = try(element(var.package_managers.go, 0), "")
      HAS_PYPI              = length(var.package_managers.pypi) == 0 ? "" : "YES"
      PIP_CONF              = local.pip_conf
      REPOSITORY_PYPI       = try(element(var.package_managers.pypi, 0), "")
      HAS_DOCKER            = length(var.package_managers.docker) == 0 ? "" : "YES"
      REGISTER_DOCKER       = join("\n", formatlist("register_docker \"%s\"", var.package_managers.docker))
      HAS_CONDA             = length(var.package_managers.conda) == 0 ? "" : "YES"
      CONDA_CONF            = local.conda_conf
      REPOSITORY_CONDA      = try(element(var.package_managers.conda, 0), "")
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
  value    = artifactory_scoped_token.me.access_token
}

resource "coder_env" "jfrog_ide_store_connection" {
  count    = var.configure_code_server ? 1 : 0
  agent_id = var.agent_id
  name     = "JFROG_IDE_STORE_CONNECTION"
  value    = true
}

resource "coder_env" "goproxy" {
  count    = length(var.package_managers.go) == 0 ? 0 : 1
  agent_id = var.agent_id
  name     = "GOPROXY"
  value = join(",", [
    for repo in var.package_managers.go :
    "https://${local.username}:${artifactory_scoped_token.me.access_token}@${local.jfrog_host}/artifactory/api/go/${repo}"
  ])
}

output "access_token" {
  description = "value of the JFrog access token"
  value       = artifactory_scoped_token.me.access_token
  sensitive   = true
}

output "username" {
  description = "value of the JFrog username"
  value       = local.username
}
