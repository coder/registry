terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.12"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "port" {
  type        = number
  description = "The port to run Parsec web interface on."
  default     = 8000
}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation."
  default     = null
}

variable "group" {
  type        = string
  description = "The name of a group that this app belongs to."
  default     = null
}

variable "subdomain" {
  type        = bool
  default     = true
  description = "Is subdomain sharing enabled in your cluster?"
}

resource "coder_script" "parsec" {
  agent_id     = var.agent_id
  display_name = "Parsec"
  icon         = "/icon/parsec.svg"
  run_on_start = true
  script = templatefile("${path.module}/run.sh", {
    PORT = var.port
  })
  timeout = 300
}

resource "coder_app" "parsec" {
  agent_id     = var.agent_id
  slug         = "parsec"
  display_name = "Parsec"
  url          = "http://localhost:${var.port}"
  icon         = "/icon/parsec.svg"
  subdomain    = var.subdomain
  share        = "owner"
  order        = var.order
  group        = var.group

  healthcheck {
    url       = "http://localhost:${var.port}"
    interval  = 5
    threshold = 10
  }
}

output "parsec_url" {
  description = "The URL to access Parsec"
  value       = "http://localhost:${var.port}"
}
