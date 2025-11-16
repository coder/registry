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

variable "install_version" {
  type        = string
  description = "The version of AWS CLI to install."
  default     = ""
}

variable "download_url" {
  type        = string
  description = "Custom download URL for AWS CLI. Useful for airgapped environments. If not set, uses the official AWS download URL."
  default     = ""
}

variable "log_path" {
  type        = string
  description = "The path to the AWS CLI installation log file."
  default     = "/tmp/aws-cli-install.log"
}

resource "coder_script" "aws-cli" {
  agent_id     = var.agent_id
  display_name = "AWS CLI"
  icon         = "/icon/aws.svg"
  script = templatefile("${path.module}/run.sh", {
    LOG_PATH : var.log_path,
    VERSION : var.install_version,
    DOWNLOAD_URL : var.download_url,
  })
  run_on_start = true
  run_on_stop  = false
}
