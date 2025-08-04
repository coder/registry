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

variable "streaming_server" {
  type        = string
  description = "The streaming server to use: 'gamestream' for NVIDIA GameStream or 'sunshine' for Sunshine server."
  default     = "sunshine"
  
  validation {
    condition     = contains(["gamestream", "sunshine"], var.streaming_server)
    error_message = "Invalid streaming server. Please specify either 'gamestream' or 'sunshine'."
  }
}

variable "port" {
  type        = number
  description = "The port for the streaming server web interface."
  default     = 47990
}

variable "sunshine_version" {
  type        = string
  description = "Version of Sunshine to install when using sunshine streaming server."
  default     = "v0.22.2"
}

variable "enable_audio" {
  type        = bool
  description = "Enable audio streaming support."
  default     = true
}

variable "enable_gamepad" {
  type        = bool
  description = "Enable gamepad/controller support."
  default     = true
}

variable "resolution" {
  type        = string
  description = "Default streaming resolution."
  default     = "1920x1080"
  
  validation {
    condition = can(regex("^[0-9]+x[0-9]+$", var.resolution))
    error_message = "Resolution must be in format WIDTHxHEIGHT (e.g., 1920x1080)."
  }
}

variable "fps" {
  type        = number
  description = "Default streaming frame rate."
  default     = 60
  
  validation {
    condition     = var.fps >= 30 && var.fps <= 120
    error_message = "FPS must be between 30 and 120."
  }
}

variable "bitrate" {
  type        = number
  description = "Default streaming bitrate in Mbps."
  default     = 20
  
  validation {
    condition     = var.bitrate >= 5 && var.bitrate <= 150
    error_message = "Bitrate must be between 5 and 150 Mbps."
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

variable "subdomain" {
  type        = bool
  default     = true
  description = "Is subdomain sharing enabled in your cluster?"
}

variable "share" {
  type    = string
  default = "owner"
  validation {
    condition     = var.share == "owner" || var.share == "authenticated" || var.share == "public"
    error_message = "Incorrect value. Please set either 'owner', 'authenticated', or 'public'."
  }
}

locals {
  display_name = var.streaming_server == "gamestream" ? "NVIDIA GameStream" : "Sunshine"
  icon_path    = var.streaming_server == "gamestream" ? "/icon/nvidia.svg" : "/icon/sunshine.svg"
}

resource "coder_script" "moonlight_setup" {
  agent_id     = var.agent_id
  display_name = "Moonlight Setup"
  icon         = local.icon_path
  run_on_start = true
  script = templatefile("${path.module}/setup.sh.tftpl", {
    STREAMING_SERVER = var.streaming_server
    PORT            = var.port
    SUNSHINE_VERSION = var.sunshine_version
    ENABLE_AUDIO    = var.enable_audio
    ENABLE_GAMEPAD  = var.enable_gamepad
    RESOLUTION      = var.resolution
    FPS             = var.fps
    BITRATE         = var.bitrate
    SUBDOMAIN       = tostring(var.subdomain)
  })
}

resource "coder_app" "moonlight_web" {
  count        = var.streaming_server == "sunshine" ? 1 : 0
  agent_id     = var.agent_id
  slug         = "moonlight-web"
  display_name = "Sunshine Web UI"
  url          = "https://localhost:${var.port}"
  icon         = "/icon/sunshine.svg"
  subdomain    = var.subdomain
  share        = var.share
  order        = var.order
  group        = var.group

  healthcheck {
    url       = "https://localhost:${var.port}"
    interval  = 10
    threshold = 6
  }
}

resource "coder_app" "moonlight_docs" {
  agent_id     = var.agent_id
  display_name = "Moonlight Client Downloads"
  slug         = "moonlight-docs"
  icon         = "/icon/desktop.svg"
  url          = "https://moonlight-stream.org"
  share        = var.share
  order        = var.order
  group        = var.group
}

resource "coder_app" "gamestream_guide" {
  count        = var.streaming_server == "gamestream" ? 1 : 0
  agent_id     = var.agent_id
  display_name = "GameStream Setup Guide"
  slug         = "gamestream-guide"
  icon         = "/icon/nvidia.svg"
  url          = "https://www.nvidia.com/en-us/support/gamestream/"
  share        = var.share
  order        = var.order
  group        = var.group
}
