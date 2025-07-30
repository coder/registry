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

variable "coder_github_auth_id" {
  type        = string
  description = "The ID of the GitHub external auth."
  default     = "github"
}

variable "vault_github_auth_path" {
  type        = string
  description = "The path to the GitHub auth method."
  default     = "github"
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
  display_name = "Vault (GitHub)"
  icon         = "/icon/vault.svg"
  script = templatefile("${path.module}/run.sh", {
    AUTH_PATH : var.vault_github_auth_path,
    GITHUB_EXTERNAL_AUTH_ID : data.coder_external_auth.github.id,
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

data "coder_external_auth" "github" {
  id = var.coder_github_auth_id
}
