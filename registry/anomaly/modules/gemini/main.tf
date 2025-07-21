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
  default     = "/icon/gemini.svg"
}

variable "folder" {
  type        = string
  description = "The folder to run Gemini in."
  default     = "/home/coder"
}

variable "install_gemini" {
  type        = bool
  description = "Whether to install Gemini."
  default     = true
}

variable "gemini_version" {
  type        = string
  description = "The version of Gemini to install."
  default     = ""
}

variable "gemini_settings_json" {
  type        = string
  description = "json to use in ~/.gemini/settings.json."
  default     = ""
}

variable "gemini_api_key" {
  type        = string
  description = "Gemini API Key"
  default     = ""
}

variable "google_genai_use_vertexai" {
  type        = bool
  description = "Whether to use vertex ai"
  default     = false
}

variable "install_agentapi" {
  type        = bool
  description = "Whether to install AgentAPI."
  default     = true
}

variable "agentapi_version" {
  type        = string
  description = "The version of AgentAPI to install."
  default     = "v0.2.3"
}

variable "gemini_model" {
  type        = string
  description = "The model to use for Gemini (e.g., claude-3-5-sonnet-latest)."
  default     = ""
}

variable "gemini_start_directory" {
  type        = string
  description = "Directory to start the Gemini CLI in."
  default     = "/home/coder/gemini"
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Goose."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Gemini."
  default     = null
}


locals {
  app_slug        = "gemini"
  install_script  = file("${path.module}/scripts/install.sh")
  start_script    = file("${path.module}/scripts/start.sh")
  module_dir_name = ".gemini-module"
}

module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "1.0.0"

  agent_id             = var.agent_id
  web_app_slug         = local.app_slug
  web_app_order        = var.order
  web_app_group        = var.group
  web_app_icon         = var.icon
  web_app_display_name = "Gemini"
  cli_app_slug         = "${local.app_slug}-cli"
  cli_app_display_name = "Gemini CLI"
  module_dir_name      = local.module_dir_name
  install_agentapi     = var.install_agentapi
  agentapi_version     = var.agentapi_version
  pre_install_script   = var.pre_install_script
  post_install_script  = var.post_install_script
  start_script         = <<-EOT
     #!/bin/bash
     set -o errexit
     set -o pipefail

     echo -n '${base64encode(local.start_script)}' | base64 -d > /tmp/start.sh
     chmod +x /tmp/start.sh
     GOOGLE_API_KEY='${var.gemini_api_key}' \
     GOOGLE_GENAI_USE_VERTEXAI='${var.google_genai_use_vertexai}' \
     GEMINI_MODEL='${var.gemini_model}' \
     GEMINI_START_DIRECTORY='${var.gemini_start_directory}' \
     /tmp/start.sh
   EOT

  install_script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh
    ARG_INSTALL='${var.install_gemini}' \
    ARG_GEMINI_VERSION='${var.gemini_version}' \
    ARG_GEMINI_CONFIG='${var.gemini_settings_json}' \
    /tmp/install.sh
  EOT
}
