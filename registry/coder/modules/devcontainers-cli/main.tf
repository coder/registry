terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
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
  description = "The @devcontainers/cli version to install: latest, X.Y.Z, or vX.Y.Z."
  type        = string
  default     = "latest"

  validation {
    condition     = can(regex("^(latest|v?(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*))$", var.devcontainers_cli_version))
    error_message = "devcontainers_cli_version must be latest or an exact version in X.Y.Z or vX.Y.Z format."
  }
}

locals {
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    DEVCONTAINERS_CLI_VERSION_B64 = base64encode(trimprefix(var.devcontainers_cli_version, "v"))
  })
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.2"

  agent_id            = var.agent_id
  module_directory    = "$HOME/.coder-modules/coder/devcontainers-cli"
  display_name_prefix = "devcontainers-cli"
  icon                = "/icon/devcontainers.svg"
  install_script      = local.install_script
}

# coder-utils does not expose start_blocks_login; only this optional waiter blocks login.
resource "coder_script" "wait_for_install" {
  count              = var.start_blocks_login ? 1 : 0
  agent_id           = var.agent_id
  display_name       = "devcontainers-cli: Wait for Installation"
  icon               = "/icon/devcontainers.svg"
  run_on_start       = true
  start_blocks_login = true
  script             = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    trap 'coder exp sync complete coder-devcontainers-cli-login' EXIT
    coder exp sync want coder-devcontainers-cli-login ${join(" ", module.coder_utils.scripts)}
    coder exp sync start coder-devcontainers-cli-login
  EOT
}

output "scripts" {
  description = "Ordered list of coder exp sync names produced by the installation pipeline."
  value       = module.coder_utils.scripts
}
