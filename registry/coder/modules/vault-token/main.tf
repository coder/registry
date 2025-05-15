terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.12.4"
    }
  }
}

# Add required variables for your modules and remove any unneeded variables
variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "vault_addr" {
  type        = string
  description = "The address of the Vault server."
}

variable "vault_token" {
  type        = string
  description = "The Vault token to use for authentication."
  sensitive   = true
  default     = null
}

variable "vault_cli_version" {
  type        = string
  description = "The version of Vault to install."
  default     = "latest"
  validation {
    condition     = can(regex("^(latest|[0-9]+\\.[0-9]+\\.[0-9]+)$", var.vault_cli_version))
    error_message = "Vault version must be in the format 0.0.0 or latest"
  }
}

data "coder_workspace" "me" {}

resource "coder_script" "vault" {
  agent_id     = var.agent_id
  display_name = "Vault (Token)"
  icon         = "/icon/vault.svg"
  script = templatefile("${path.module}/run.sh", {
    INSTALL_VERSION : var.vault_cli_version,
  })
  run_on_start       = true
  start_blocks_login = true
}

resource "coder_env" "vault_addr" {
  agent_id = var.agent_id
  name     = "VAULT_ADDR"
  value    = var.vault_addr
}

resource "coder_env" "vault_token" {
  count    = var.vault_token != null ? 1 : 0
  agent_id = var.agent_id
  name     = "VAULT_TOKEN"
  value    = var.vault_token
}
