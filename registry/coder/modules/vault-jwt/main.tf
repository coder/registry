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

variable "vault_jwt_auth_path" {
  type        = string
  description = "The path to the Vault JWT auth method."
  default     = "jwt"
}

variable "vault_jwt_role" {
  type        = string
  description = "The name of the Vault role to use for authentication."
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

resource "coder_script" "vault" {
  agent_id     = var.agent_id
  display_name = "Vault (GitHub)"
  icon         = "/icon/vault.svg"
  script = templatefile("${path.module}/run.sh", {
    CODER_OIDC_ACCESS_TOKEN : data.coder_workspace_owner.me.oidc_access_token,
    VAULT_JWT_AUTH_PATH : var.vault_jwt_auth_path,
    VAULT_JWT_ROLE : var.vault_jwt_role,
    VAULT_CLI_VERSION : var.vault_cli_version,
  })
  run_on_start       = true
  start_blocks_login = true
}

resource "coder_env" "vault_addr" {
  agent_id = var.agent_id
  name     = "VAULT_ADDR"
  value    = var.vault_addr
}

data "coder_workspace_owner" "me" {}
