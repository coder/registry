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
  description = "The Gemini API key. Obtain from https://aistudio.google.com/app/apikey"
  default     = ""
  sensitive   = true
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


variable "additional_extensions" {
  type        = string
  description = "Additional extensions configuration in json format to append to the config."
  default     = null
}

variable "gemini_instruction_prompt" {
  type        = string
  description = "Instruction prompt for Gemini. It will be added to GEMINI.md in the specified folder."
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

  # we have to trim the slash because otherwise coder exp mcp will
  # set up an invalid gemini config
  workdir                            = trimsuffix(var.folder, "/")
  app_slug                           = "gemini"
  install_script                     = file("${path.module}/scripts/install.sh")
  start_script                       = file("${path.module}/scripts/agentapi-start.sh")
  agentapi_wait_for_start_script_b64 = base64encode(file("${path.module}/scripts/agentapi-wait-for-start.sh"))
  remove_last_session_id_script_b64  = base64encode(file("${path.module}/scripts/remove-last-session-id.js"))
  module_dir_name                    = ".gemini-module"
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

     # this must be kept in sync with the agentapi-start.sh script
     module_path="$HOME/.gemini-module"
     mkdir -p "$module_path/scripts"

     echo -n "$CODER_MCP_GEMINI_TASK_PROMPT" > "$module_path/prompt.txt"

     echo -n "${local.remove_last_session_id_script_b64}" | base64 -d > "$module_path/scripts/remove-last-session-id.js"
     echo -n "${local.agentapi_wait_for_start_script_b64}" | base64 -d > "$module_path/scripts/agentapi-wait-for-start.sh"
     chmod +x "$module_path/scripts/agentapi-wait-for-start.sh"

     echo -n '${base64encode(local.start_script)}' | base64 -d > /tmp/agentapi-start.sh
     chmod +x /tmp/agentapi-start.sh
     
     export LANG=en_US.UTF-8
     export LC_ALL=en_US.UTF-8
     
     cd "${local.workdir}"
     nohup env GEMINI_API_KEY='${var.gemini_api_key}' \
     GOOGLE_GENAI_USE_VERTEXAI='${var.use_vertexai}' \
     GEMINI_MODEL='${var.gemini_model}' \
     GEMINI_START_DIRECTORY='${local.workdir}' \
     CODER_MCP_GEMINI_TASK_PROMPT='$CODER_MCP_GEMINI_TASK_PROMPT' \
     /tmp/agentapi-start.sh use_prompt &> "$module_path/agentapi-start.log" &
     "$module_path/scripts/agentapi-wait-for-start.sh"
   EOT

  install_script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    if [ ! -d "${local.workdir}" ]; then
      echo "Warning: The specified folder '${local.workdir}' does not exist."
      echo "Creating the folder..."
      mkdir -p "${local.workdir}"
      echo "Folder created successfully."
    fi

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh
    ARG_INSTALL='${var.install_gemini}' \
    ARG_GEMINI_VERSION='${var.gemini_version}' \
    ARG_GEMINI_CONFIG='${base64encode(var.gemini_settings_json)}' \
    BASE_EXTENSIONS='${base64encode(replace(local.base_extensions, "'", "'\\''"))}' \
    ADDITIONAL_EXTENSIONS='${base64encode(replace(var.additional_extensions != null ? var.additional_extensions : "", "'", "'\\''"))}' \
    GEMINI_START_DIRECTORY='${local.workdir}' \
    GEMINI_INSTRUCTION_PROMPT='${base64encode(var.gemini_instruction_prompt)}' \
    /tmp/install.sh
  EOT
}