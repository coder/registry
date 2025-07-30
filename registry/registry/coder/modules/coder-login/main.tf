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

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_script" "coder-login" {
  agent_id = var.agent_id
  script = templatefile("${path.module}/run.sh", {
    CODER_USER_TOKEN : data.coder_workspace_owner.me.session_token,
    CODER_DEPLOYMENT_URL : data.coder_workspace.me.access_url
  })
  display_name       = "Coder Login"
  icon               = "/icon/coder.svg"
  run_on_start       = true
  start_blocks_login = true
}

