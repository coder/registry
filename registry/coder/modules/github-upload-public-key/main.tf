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

variable "key_name" {
  description = "The title assigned to the uploaded SSH key in GitHub. Defaults to '<Coder access URL> Workspaces'."
  type        = string
  default     = null
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_script" "github_upload_public_key" {
  agent_id = var.agent_id
  script = templatefile("${path.module}/run.sh", {
    CODER_OWNER_SESSION_TOKEN : data.coder_workspace_owner.me.session_token,
    CODER_ACCESS_URL : data.coder_workspace.me.access_url,
    CODER_EXTERNAL_AUTH_ID : var.external_auth_id,
    GITHUB_API_URL : var.github_api_url,
    CODER_PUBLIC_KEY_NAME : var.key_name == null ? "" : var.key_name,
  })
  display_name = "Github Upload Public Key"
  icon         = "/icon/github.svg"
  run_on_start = true
}
