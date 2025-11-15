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

variable "aws_cli_version" {
  type        = string
  description = "The version of AWS CLI to install. Leave empty for latest."
  default     = ""
}

variable "install_directory" {
  type        = string
  description = "The directory to install AWS CLI to."
  default     = "/usr/local"
}

variable "architecture" {
  type        = string
  description = "The architecture to install AWS CLI for. Valid values are 'x86_64' and 'aarch64'. Leave empty for auto-detection."
  default     = ""
  validation {
    condition     = var.architecture == "" || var.architecture == "x86_64" || var.architecture == "aarch64"
    error_message = "The 'architecture' variable must be one of: '', 'x86_64', 'aarch64'."
  }
}

variable "verify_signature" {
  type        = bool
  description = "Whether to verify the GPG signature of the downloaded installer."
  default     = false
}

resource "coder_script" "aws-cli" {
  agent_id     = var.agent_id
  display_name = "AWS CLI"
  icon         = "/icon/aws.svg"
  script = templatefile("${path.module}/run.sh", {
    VERSION : var.aws_cli_version,
    INSTALL_DIRECTORY : var.install_directory,
    ARCHITECTURE : var.architecture,
    VERIFY_SIGNATURE : var.verify_signature
  })
  run_on_start = true
}

output "aws_cli_version" {
  description = "The version of AWS CLI that was installed (or 'latest' if no version was specified)."
  value       = var.aws_cli_version != "" ? var.aws_cli_version : "latest"
}
