terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.7"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  default     = null
}

variable "group" {
  type        = string
  description = "The name of a group that this app belongs to."
  default     = null
}

variable "icon" {
  type        = string
  description = "The icon to use for the app."
  default     = "/icon/goose.svg"
}

variable "folder" {
  type        = string
  description = "The folder to run Goose in."
  default     = "/home/coder"
}

variable "install_goose" {
  type        = bool
  description = "Whether to install Goose."
  default     = true
}

variable "goose_version" {
  type        = string
  description = "The version of Goose to install."
  default     = "stable"
}

variable "install_agentapi" {
  type        = bool
  description = "Whether to install AgentAPI."
  default     = true
}

variable "agentapi_version" {
  type        = string
  description = "The version of AgentAPI to install."
  default     = "v0.3.3"
}

variable "subdomain" {
  type        = bool
  description = "Whether to use a subdomain for AgentAPI."
  default     = false
}

variable "goose_provider" {
  type        = string
  description = "The provider to use for Goose (e.g., anthropic)."
}

variable "goose_model" {
  type        = string
  description = "The model to use for Goose (e.g., claude-3-5-sonnet-latest)."
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Goose."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Goose."
  default     = null
}

variable "additional_extensions" {
  type        = string
  description = "Additional extensions configuration in YAML format to append to the config."
  default     = null
}

locals {
  app_slug        = "goose"
  base_extensions = <<-EOT
coder:
  args:
  - exp
  - mcp
  - server
  cmd: coder
  description: Report ALL tasks and statuses (in progress, done, failed) you are working on.
  enabled: true
  envs:
    CODER_MCP_APP_STATUS_SLUG: ${local.app_slug}
    CODER_MCP_AI_AGENTAPI_URL: http://localhost:3284
  name: Coder
  timeout: 3000
  type: stdio
developer:
  display_name: Developer
  enabled: true
  name: developer
  timeout: 300
  type: builtin
EOT

  # Add two spaces to each line of extensions to match YAML structure
  formatted_base        = "  ${replace(trimspace(local.base_extensions), "\n", "\n  ")}"
  additional_extensions = var.additional_extensions != null ? "\n  ${replace(trimspace(var.additional_extensions), "\n", "\n  ")}" : ""
  combined_extensions   = <<-EOT
extensions:
${local.formatted_base}${local.additional_extensions}
EOT
  install_script        = file("${path.module}/scripts/install.sh")
  start_script          = file("${path.module}/scripts/start.sh")
  module_dir_name       = ".goose-module"
}

module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "1.1.1"

  agent_id             = var.agent_id
  web_app_slug         = local.app_slug
  web_app_order        = var.order
  web_app_group        = var.group
  web_app_icon         = var.icon
  web_app_display_name = "Goose"
  cli_app_slug         = "${local.app_slug}-cli"
  cli_app_display_name = "Goose CLI"
  module_dir_name      = local.module_dir_name
  install_agentapi     = var.install_agentapi
  agentapi_version     = var.agentapi_version
  agentapi_subdomain   = var.subdomain
  pre_install_script   = var.pre_install_script
  post_install_script  = var.post_install_script
  start_script         = local.start_script
  install_script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh

    ARG_PROVIDER='${var.goose_provider}' \
    ARG_MODEL='${var.goose_model}' \
    ARG_GOOSE_CONFIG="$(echo -n '${base64encode(local.combined_extensions)}' | base64 -d)" \
    ARG_INSTALL='${var.install_goose}' \
    ARG_GOOSE_VERSION='${var.goose_version}' \
    /tmp/install.sh
  EOT
}
