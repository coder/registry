terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

variable "nexus_url" {
  type        = string
  description = "The base URL of your Nexus repository manager (e.g. https://nexus.example.com)"
  validation {
    condition     = can(regex("^(https|http)://", var.nexus_url))
    error_message = "nexus_url must be a valid URL starting with either 'https://' or 'http://'"
  }
}

variable "nexus_username" {
  type        = string
  description = "Custom username for Nexus authentication. If not provided, defaults to the Coder username based on the username_field setting"
  default     = null
}

variable "nexus_password" {
  type        = string
  description = "API token or password for Nexus authentication. This value is sensitive and should be stored securely"
  sensitive   = true
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "package_managers" {
  type = object({
    maven  = optional(list(string), [])
    npm    = optional(list(string), [])
    go     = optional(list(string), [])
    pypi   = optional(list(string), [])
    docker = optional(list(string), [])
  })
  default = {
    maven  = []
    npm    = []
    go     = []
    pypi   = []
    docker = []
  }
  description = <<-EOF
    Configuration for package managers. Each key maps to a list of Nexus repository names:
    - maven: List of Maven repository names
    - npm: List of npm repository names (supports scoped packages with "@scope:repo-name")
    - go: List of Go proxy repository names
    - pypi: List of PyPI repository names
    - docker: List of Docker registry names
    Unused package managers can be omitted.
    Example:
      {
        maven  = ["maven-public", "maven-releases"]
        npm    = ["npm-public", "@scoped:npm-private"]
        go     = ["go-public", "go-private"]
        pypi   = ["pypi-public", "pypi-private"]
        docker = ["docker-public", "docker-private"]
      }
  EOF
}

variable "username_field" {
  type        = string
  description = "Field to use for username (\"username\" or \"email\"). Defaults to \"username\". Only used when nexus_username is not provided"
  default     = "username"
  validation {
    condition     = can(regex("^(email|username)$", var.username_field))
    error_message = "username_field must be either 'email' or 'username'"
  }
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  username   = coalesce(var.nexus_username, var.username_field == "email" ? data.coder_workspace_owner.me.email : data.coder_workspace_owner.me.name)
  nexus_host = split("/", replace(replace(var.nexus_url, "https://", ""), "http://", ""))[0]
}

locals {
  # Get first repository name or use default
  maven_repo = length(var.package_managers.maven) > 0 ? var.package_managers.maven[0] : "maven-public"
  npm_repo   = length(var.package_managers.npm) > 0 ? var.package_managers.npm[0] : "npm-public"
  go_repo    = length(var.package_managers.go) > 0 ? var.package_managers.go[0] : "go-public"
  pypi_repo  = length(var.package_managers.pypi) > 0 ? var.package_managers.pypi[0] : "pypi-public"

  npmrc = <<-EOF
registry=${var.nexus_url}/repository/${local.npm_repo}/
//${local.nexus_host}/repository/${local.npm_repo}/:username=${local.username}
//${local.nexus_host}/repository/${local.npm_repo}/:_password=${base64encode(var.nexus_password)}
//${local.nexus_host}/repository/${local.npm_repo}/:always-auth=true
EOF
}

resource "coder_script" "nexus" {
  agent_id     = var.agent_id
  display_name = "nexus"
  icon         = "/icon/nexus.svg"
  script = templatefile("${path.module}/run.sh", {
    NEXUS_URL       = var.nexus_url
    NEXUS_HOST      = local.nexus_host
    NEXUS_USERNAME  = local.username
    NEXUS_PASSWORD  = var.nexus_password
    HAS_MAVEN       = length(var.package_managers.maven) == 0 ? "" : "YES"
    MAVEN_REPO      = local.maven_repo
    HAS_NPM         = length(var.package_managers.npm) == 0 ? "" : "YES"
    NPMRC           = local.npmrc
    HAS_GO          = length(var.package_managers.go) == 0 ? "" : "YES"
    GO_REPO         = local.go_repo
    HAS_PYPI        = length(var.package_managers.pypi) == 0 ? "" : "YES"
    PYPI_REPO       = local.pypi_repo
    HAS_DOCKER      = length(var.package_managers.docker) == 0 ? "" : "YES"
    REGISTER_DOCKER = join("\n    ", formatlist("register_docker \"%s\"", var.package_managers.docker))
  })
  run_on_start = true
}

resource "coder_env" "goproxy" {
  count    = length(var.package_managers.go) == 0 ? 0 : 1
  agent_id = var.agent_id
  name     = "GOPROXY"
  value = join(",", [
    for repo in var.package_managers.go :
    "https://${local.username}:${var.nexus_password}@${local.nexus_host}/repository/${repo}"
  ])
}

