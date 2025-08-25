terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  # Fallback config with CSP for Coder iframe embedding when user config is empty
  csp_fallback_config = {
    ServerApp = {
      tornado_settings = {
        headers = {
          "Content-Security-Policy" = "frame-ancestors 'self' ${data.coder_workspace.me.access_url}"
        }
      }
    }
  }

  # Use user config if provided, otherwise fallback to CSP config
  config_json = var.config == "{}" ? jsonencode(local.csp_fallback_config) : var.config
  config_b64  = base64encode(local.config_json)
}

# Add required variables for your modules and remove any unneeded variables
variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "log_path" {
  type        = string
  description = "The path to log jupyterlab to."
  default     = "/tmp/jupyterlab.log"
}

variable "port" {
  type        = number
  description = "The port to run jupyterlab on."
  default     = 19999
}

variable "share" {
  type    = string
  default = "owner"
  validation {
    condition     = var.share == "owner" || var.share == "authenticated" || var.share == "public"
    error_message = "Incorrect value. Please set either 'owner', 'authenticated', or 'public'."
  }
}

variable "subdomain" {
  type        = bool
  description = "Determines whether JupyterLab will be accessed via its own subdomain or whether it will be accessed via a path on Coder."
  default     = true
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

variable "config" {
  type        = string
  description = "A JSON string of JupyterLab server configuration settings. When set, writes ~/.jupyter/jupyter_server_config.json."
  default     = "{}"
}

resource "coder_script" "jupyterlab_config" {
  agent_id           = var.agent_id
  display_name       = "JupyterLab Config"
  icon               = "/icon/jupyter.svg"
  run_on_start       = true
  start_blocks_login = false
  script             = <<-EOT
    #!/bin/sh
    set -eu
    mkdir -p "$HOME/.jupyter"
    echo -n "${local.config_b64}" | base64 -d > "$HOME/.jupyter/jupyter_server_config.json"
  EOT
}

resource "coder_script" "jupyterlab" {
  agent_id     = var.agent_id
  display_name = "jupyterlab"
  icon         = "/icon/jupyter.svg"
  script = templatefile("${path.module}/run.sh", {
    LOG_PATH : var.log_path,
    PORT : var.port
    BASE_URL : var.subdomain ? "" : "/@${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name}/apps/jupyterlab"
  })
  run_on_start = true
}

resource "coder_app" "jupyterlab" {
  agent_id     = var.agent_id
  slug         = "jupyterlab" # sync with the usage in URL
  display_name = "JupyterLab"
  url          = var.subdomain ? "http://localhost:${var.port}" : "http://localhost:${var.port}/@${data.coder_workspace_owner.me.name}/${data.coder_workspace.me.name}/apps/jupyterlab"
  icon         = "/icon/jupyter.svg"
  subdomain    = var.subdomain
  share        = var.share
  order        = var.order
  group        = var.group
  healthcheck {
    url       = "http://localhost:${var.port}/api"
    interval  = 5
    threshold = 6
  }
}
