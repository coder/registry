terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.12.4"
    }
    hcp = {
      source  = "hashicorp/hcp"
      version = ">= 0.82.0"
    }
  }
}

provider "hcp" {
  client_id     = var.client_id
  client_secret = var.client_secret
  project_id    = var.project_id
}

provider "coder" {}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "project_id" {
  type        = string
  description = "The ID of the HCP project."
}

variable "client_id" {
  type        = string
  description = <<-EOF
  The client ID for the HCP Vault Secrets service principal. (Optional if HCP_CLIENT_ID is set as an environment variable.)
  EOF
  default     = null
  sensitive   = true
}

variable "client_secret" {
  type        = string
  description = <<-EOF
  The client secret for the HCP Vault Secrets service principal. (Optional if HCP_CLIENT_SECRET is set as an environment variable.)
  EOF
  default     = null
  sensitive   = true
}

variable "app_name" {
  type        = string
  description = "The name of the secrets app in HCP Vault Secrets"
}

variable "secrets" {
  type        = list(string)
  description = "The names of the secrets to retrieve from HCP Vault Secrets"
  default     = null
}

data "hcp_vault_secrets_app" "secrets" {
  app_name = var.app_name
}

resource "coder_env" "hvs_secrets" {
  # https://support.hashicorp.com/hc/en-us/articles/4538432032787-Variable-has-a-sensitive-value-and-cannot-be-used-as-for-each-arguments
  for_each = var.secrets != null ? toset(var.secrets) : nonsensitive(toset(keys(data.hcp_vault_secrets_app.secrets.secrets)))
  agent_id = var.agent_id
  name     = each.key
  value    = data.hcp_vault_secrets_app.secrets.secrets[each.key]
}