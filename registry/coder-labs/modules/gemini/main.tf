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

variable "use_vertexai" {
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
  default     = "v0.3.0"
}

variable "gemini_model" {
  type        = string
  description = "The model to use for Gemini (e.g., gemini-2.5-pro)."
  default     = ""
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Gemini."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Gemini."
  default     = null
}

data "coder_parameter" "ai_prompt" {
  type        = "string"
  name        = "AI Prompt"
  default     = ""
  description = "Initial prompt for the Gemini CLI"
  mutable     = true
}

variable "additional_extensions" {
  type        = string
  description = "Additional extensions configuration in json format to append to the config."
  default     = null
}

variable "gemini_system_prompt" {
  type        = string
  description = "System prompt for Gemini. It will be added to GEMINI.md in the specified folder."
  default     = ""
}

resource "coder_env" "gemini_api_key" {
  agent_id = var.agent_id
  name     = "GEMINI_API_KEY"
  value    = var.gemini_api_key
}

resource "coder_env" "gemini_use_vertex_ai" {
  agent_id = var.agent_id
  name     = "GOOGLE_GENAI_USE_VERTEXAI"
  value    = var.use_vertexai
}

locals {
  base_extensions = <<-EOT
{
  "coder": {
    "args": [
      "exp",
      "mcp",
      "server"
    ],
    "command": "coder",
    "description": "Report ALL tasks and statuses (in progress, done, failed) you are working on.",
    "enabled": true,
    "env": {
      "CODER_MCP_APP_STATUS_SLUG": "${local.app_slug}",
      "CODER_MCP_AI_AGENTAPI_URL": "http://localhost:3284"
    },
    "name": "Coder",
    "timeout": 3000,
    "type": "stdio",
    "trust": true
  }
}
EOT

  app_slug        = "gemini"
  install_script  = file("${path.module}/scripts/install.sh")
  start_script    = file("${path.module}/scripts/start.sh")
  module_dir_name = ".gemini-module"
}

module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "1.1.1"

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
     GEMINI_API_KEY='${var.gemini_api_key}' \
     GOOGLE_GENAI_USE_VERTEXAI='${var.use_vertexai}' \
     GEMINI_MODEL='${var.gemini_model}' \
     GEMINI_START_DIRECTORY='${var.folder}' \
     GEMINI_TASK_PROMPT='${base64encode(data.coder_parameter.ai_prompt.value)}' \
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
    ARG_GEMINI_CONFIG='${base64encode(var.gemini_settings_json)}' \
    BASE_EXTENSIONS='${base64encode(replace(local.base_extensions, "'", "'\\''"))}' \
    ADDITIONAL_EXTENSIONS='${base64encode(replace(var.additional_extensions != null ? var.additional_extensions : "", "'", "'\\''"))}' \
    GEMINI_START_DIRECTORY='${var.folder}' \
    GEMINI_INSTRUCTION_PROMPT='${base64encode(var.gemini_system_prompt)}' \
    /tmp/install.sh
  EOT
}