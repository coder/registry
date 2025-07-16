terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The agent to install pgAdmin on."
}

variable "port" {
  type        = number
  description = "The port to run pgAdmin on."
  default     = 5050
}

variable "subdomain" {
  type        = bool
  description = "If true, the app will be served on a subdomain."
  default     = true
}

data "coder_workspace" "me" {}

resource "coder_app" "pgadmin" {
  count        = data.coder_workspace.me.start_count
  agent_id     = var.agent_id
  display_name = "pgAdmin"
  slug         = "pgadmin"
  icon         = "/icon/postgres.svg"
  url          = var.subdomain ? "https://pgadmin-${data.coder_workspace.me.id}.${data.coder_workspace.me.access_url}" : "http://localhost:${var.port}"
  share        = "owner"
}

resource "coder_script" "pgadmin" {
  agent_id     = var.agent_id
  display_name = "Install and run pgAdmin"
  icon         = "/icon/postgres.svg"
  run_on_start = true
  script = templatefile("${path.module}/run.sh", {
    PORT     = var.port,
    LOG_PATH = "/tmp/pgadmin.log"
  })
}