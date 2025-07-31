terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.7"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "parsec_host_key" {
  type        = string
  description = "The Parsec host key for authentication. Can be obtained from https://console.parsec.app/settings"
  sensitive   = true
}

variable "parsec_version" {
  type        = string
  description = "The version of Parsec to install. Use 'latest' for the most recent version."
  default     = "latest"
}

variable "enable_gpu_acceleration" {
  type        = bool
  description = "Whether to enable GPU acceleration for Parsec streaming."
  default     = true
}

variable "auto_start" {
  type        = bool
  description = "Whether to automatically start Parsec daemon on workspace startup."
  default     = true
}

variable "parsec_config" {
  type = object({
    encoder_bitrate   = optional(number, 50) # Mbps
    encoder_fps       = optional(number, 60)
    bandwidth_limit   = optional(number, 100) # Mbps
    encoder_h265     = optional(bool, true)
    client_keyboard_layout = optional(string, "en-us")
  })
  description = "Parsec configuration options"
  default = {}
}

data "coder_workspace" "me" {}

resource "coder_script" "install_parsec" {
  agent_id     = var.agent_id
  display_name = "Install Parsec"
  icon         = "/icon/parsec.svg"
  script       = file("${path.module}/scripts/install.sh")
  run_on_start = true

  env = {
    PARSEC_HOST_KEY         = var.parsec_host_key
    PARSEC_VERSION         = var.parsec_version
    ENABLE_GPU            = tostring(var.enable_gpu_acceleration)
    AUTO_START           = tostring(var.auto_start)
    PARSEC_CONFIG        = jsonencode(var.parsec_config)
  }
}
