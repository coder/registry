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

variable "service_account_token" {
  type        = string
  description = <<-EOF
  A 1Password service account token used to authenticate the CLI.
  If set, account-based sign-in is skipped entirely.
  EOF
  default     = ""
  sensitive   = true
}

variable "account_address" {
  type        = string
  description = "The 1Password account sign-in address (e.g. teamcoder.1password.com)."
  default     = ""
}

variable "account_email" {
  type        = string
  description = "The email address for the 1Password account."
  default     = ""
}

variable "account_secret_key" {
  type        = string
  description = "The Secret Key for the 1Password account."
  default     = ""
  sensitive   = true
}

variable "install_dir" {
  type        = string
  description = "The directory to install the 1Password CLI to."
  default     = "/usr/local/bin"
}

variable "op_cli_version" {
  type        = string
  description = "The version of the 1Password CLI to install."
  default     = "latest"
  validation {
    condition     = var.op_cli_version == "latest" || can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.op_cli_version))
    error_message = "op_cli_version must be either 'latest' or a semantic version (e.g., '2.30.0')."
  }
}

data "coder_parameter" "account_password" {
  count        = var.account_address != "" && var.service_account_token == "" ? 1 : 0
  type         = "string"
  name         = "op_account_password"
  display_name = "1Password Account Password"
  description  = "Your 1Password account password. Used to sign in to the CLI."
  mutable      = true
  default      = ""
}

variable "install_vscode_extension" {
  type        = bool
  description = "Install the 1Password VS Code extension for both VS Code and code-server."
  default     = false
}

resource "coder_script" "onepassword_cli" {
  agent_id     = var.agent_id
  display_name = "1Password CLI"
  icon         = "/icon/1password.svg"
  script = templatefile("${path.module}/run.sh", {
    SERVICE_ACCOUNT_TOKEN = var.service_account_token
    ACCOUNT_ADDRESS       = var.account_address
    ACCOUNT_EMAIL         = var.account_email
    ACCOUNT_SECRET_KEY    = var.account_secret_key
    ACCOUNT_PASSWORD      = var.account_address != "" && var.service_account_token == "" ? data.coder_parameter.account_password[0].value : ""
    INSTALL_DIR              = var.install_dir
    OP_CLI_VERSION           = var.op_cli_version
    INSTALL_VSCODE_EXTENSION = var.install_vscode_extension
  })
  run_on_start       = true
  start_blocks_login = true
}

resource "coder_env" "op_service_account_token" {
  count    = var.service_account_token != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "OP_SERVICE_ACCOUNT_TOKEN"
  value    = var.service_account_token
}
