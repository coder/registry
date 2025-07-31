terraform {
  required_version = ">= 1.0"
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "os" {
  type        = string
  description = "Target operating system: 'windows' or 'linux'."
  validation {
    condition     = contains(["windows", "linux"], var.os)
    error_message = "os must be 'windows' or 'linux'"
  }
}

variable "port" {
  type        = number
  description = "Port for Parsec to listen on."
  default     = 8000
}

variable "order" {
  type        = number
  description = "Order of the app in the UI."
  default     = null
}

variable "group" {
  type        = string
  description = "Group name for the app."
  default     = null
}

variable "subdomain" {
  type        = bool
  description = "Enable subdomain sharing."
  default     = true
}

locals {
  slug         = "parsec"
  display_name = "Parsec Cloud Gaming"
  icon         = "/icon/parsec.svg"
}

resource "coder_script" "parsec_install" {
  agent_id     = var.agent_id
  display_name = "Install Parsec"
  icon         = local.icon
  run_on_start = true
  script       = var.os == "windows" ? templatefile("${path.module}/scripts/install-parsec.ps1", { PORT = var.port }) : templatefile("${path.module}/scripts/install-parsec.sh", { PORT = var.port })
}

resource "coder_app" "parsec" {
  agent_id     = var.agent_id
  slug         = local.slug
  display_name = local.display_name
  url          = var.os == "windows" ? "parsec://localhost" : "parsec://localhost"
  icon         = local.icon
  subdomain    = var.subdomain
  order        = var.order
  group        = var.group
} 