terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

provider "coder" {}

data "coder_workspace" "me" {}

resource "coder_agent" "main" {
  arch = "amd64"
  auth = "token"
  os   = "windows"
}

module "parsec" {
  source          = "../../modules/parsec"
  agent_id        = coder_agent.main.id
  parsec_host_key = var.parsec_host_key
  parsec_config = {
    encoder_bitrate = 50
    encoder_fps    = 60
    encoder_h265   = true
  }
}

variable "parsec_host_key" {
  type        = string
  description = "Your Parsec host key from https://console.parsec.app/settings"
  sensitive   = true
}
