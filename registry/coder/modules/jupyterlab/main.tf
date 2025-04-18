terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.17"
    }
  }
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

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
}
