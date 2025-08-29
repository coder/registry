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

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_external_auth" "jfrog" {
  id = var.external_auth_id
}

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
  value    = data.coder_external_auth.jfrog.access_token
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
    "https://${local.username}:${data.coder_external_auth.jfrog.access_token}@${local.jfrog_host}/artifactory/api/go/${repo}"
  ])
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
