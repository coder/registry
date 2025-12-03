terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

# Add required variables for your modules and remove any unneeded variables
variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "log_path" {
  type        = string
  description = "The path to log Open WebUI to."
  default     = "/tmp/open-webui.log"
}

variable "port" {
  type        = number
  description = "The port to run Open WebUI on."
  default     = 8080
}

variable "share" {
  type    = string
  default = "owner"
  validation {
    condition     = var.share == "owner" || var.share == "authenticated" || var.share == "public"
    error_message = "Incorrect value. Please set either 'owner', 'authenticated', or 'public'."
  }
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

resource "coder_script" "open-webui" {
  agent_id     = var.agent_id
  display_name = "open-webui"
  icon         = "/icon/openai.svg"
  script = templatefile("${path.module}/run.sh", {
    LOG_PATH : var.log_path,
    PORT : var.port,
  })
  run_on_start = true
}

resource "coder_app" "open-webui" {
  agent_id     = var.agent_id
  slug         = "open-webui"
  display_name = "Open WebUI"
  url          = "http://localhost:${var.port}"
  icon         = "/icon/openai.svg"
  subdomain    = true
  share        = var.share
  order        = var.order
  group        = var.group
}
