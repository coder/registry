terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.17"
    }
  }
}

variable "agent_id" {
  description = "The ID of a Coder agent."
  type        = string
}

variable "start_blocks_login" {
  description = "Whether workspace login waits for the devcontainers CLI installation to finish."
  type        = bool
  default     = false
}

variable "devcontainers_cli_version" {
  description = "The @devcontainers/cli version or npm dist-tag to install."
  type        = string
  default     = "latest"

  validation {
    condition     = length(trimspace(var.devcontainers_cli_version)) > 0
    error_message = "devcontainers_cli_version must not be empty."
  }
}

variable "registry_url" {
  description = "Optional npm-compatible registry URL used to install @devcontainers/cli. When unset, the selected package manager uses its configured registry."
  type        = string
  default     = null

  validation {
    condition     = var.registry_url == null || can(regex("^https?://[^\\s]+$", var.registry_url))
    error_message = "registry_url must be null or a valid HTTP(S) URL."
  }
}

resource "coder_script" "devcontainers-cli" {
  agent_id     = var.agent_id
  display_name = "devcontainers-cli"
  icon         = "/icon/devcontainers.svg"
  script = templatefile("${path.module}/run.sh", {
    DEVCONTAINERS_CLI_VERSION_B64 = base64encode(var.devcontainers_cli_version)
    REGISTRY_URL_B64              = var.registry_url != null ? base64encode(var.registry_url) : ""
  })
  run_on_start       = true
  start_blocks_login = var.start_blocks_login
}
