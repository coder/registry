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
  type        = string
  description = "The ID of a Coder agent."
}

variable "vault_addr" {
  type        = string
  description = "The address of the Vault server."
}

variable "vault_token" {
  type        = string
  description = "The Vault token to use for authentication. If not provided, only the CLI will be installed."
  default     = ""
  sensitive   = true
}

variable "install_dir" {
  type        = string
  description = "The directory to install the Vault CLI to."
  default     = "/usr/local/bin"
}

variable "vault_cli_version" {
  type        = string
  description = "The version of the Vault CLI to install."
  default     = "latest"
  validation {
    condition     = var.vault_cli_version == "latest" || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.vault_cli_version))
    error_message = "vault_cli_version must be either 'latest' or a semantic version (e.g., '1.15.0')."
  }
}

variable "vault_namespace" {
  type        = string
  description = "The Vault Enterprise namespace to use. If not provided, no namespace will be configured."
  default     = null
}

data "coder_workspace" "me" {}

resource "coder_script" "vault_cli" {
  agent_id     = var.agent_id
  display_name = "Vault CLI"
  icon         = "/icon/vault.svg"
  script = templatefile("${path.module}/run.sh", {
    VAULT_ADDR        = var.vault_addr
    VAULT_TOKEN       = var.vault_token
    INSTALL_DIR       = var.install_dir
    VAULT_CLI_VERSION = var.vault_cli_version
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
  count    = var.vault_token != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "VAULT_TOKEN"
  value    = var.vault_token
}

resource "coder_env" "vault_namespace" {
  count    = var.vault_namespace != null ? 1 : 0
  agent_id = var.agent_id
  name     = "VAULT_NAMESPACE"
  value    = var.vault_namespace
}

output "vault_cli_version" {
  description = "The version of the Vault CLI that was installed."
  value       = var.vault_cli_version
}
