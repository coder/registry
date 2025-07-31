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

variable "streaming_method" {
  type        = string
  description = "Streaming method: 'auto', 'gamestream', or 'sunshine'."
  default     = "auto"
  validation {
    condition     = contains(["auto", "gamestream", "sunshine"], var.streaming_method)
    error_message = "streaming_method must be 'auto', 'gamestream', or 'sunshine'"
  }
}

variable "port" {
  type        = number
  description = "Port for Moonlight streaming."
  default     = 47984
}

variable "quality" {
  type        = string
  description = "Streaming quality: 'low', 'medium', 'high', 'ultra'."
  default     = "high"
  validation {
    condition     = contains(["low", "medium", "high", "ultra"], var.quality)
    error_message = "quality must be 'low', 'medium', 'high', or 'ultra'"
  }
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
  slug         = "moonlight"
  display_name = "Moonlight GameStream"
  icon         = "/icon/moonlight.svg"
}

resource "coder_script" "moonlight_setup" {
  agent_id     = var.agent_id
  display_name = "Setup Moonlight Streaming"
  icon         = local.icon
  run_on_start = true
  script       = var.os == "windows" ? 
    templatefile("${path.module}/scripts/install-moonlight.ps1", { 
      STREAMING_METHOD = var.streaming_method,
      PORT = var.port,
      QUALITY = var.quality
    }) : 
    templatefile("${path.module}/scripts/install-moonlight.sh", { 
      STREAMING_METHOD = var.streaming_method,
      PORT = var.port,
      QUALITY = var.quality
    })
}

resource "coder_app" "moonlight" {
  agent_id     = var.agent_id
  slug         = local.slug
  display_name = local.display_name
  url          = "moonlight://localhost"
  icon         = local.icon
  subdomain    = var.subdomain
  order        = var.order
  group        = var.group
} 