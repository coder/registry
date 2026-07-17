terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "external_auth_id" {
  type        = string
  description = "The ID of the GitHub external auth."
  default     = "github"
}

variable "github_api_url" {
  type        = string
  description = "The URL of the GitHub instance."
  default     = "https://api.github.com"
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  script = templatefile("${path.module}/run.sh.tftpl", {
    CODER_OWNER_SESSION_TOKEN : data.coder_workspace_owner.me.session_token,
    CODER_ACCESS_URL : data.coder_workspace.me.access_url,
    CODER_EXTERNAL_AUTH_ID : var.external_auth_id,
    GITHUB_API_URL : var.github_api_url,
  })
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/.coder-modules/coder/github-upload-public-key"
  display_name_prefix = "GitHub Upload Public Key"
  icon                = "/icon/github.svg"
  install_script      = local.script
}
