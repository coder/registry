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
  default     = "/icon/sourcegraph-amp.svg"
}

variable "folder" {
  type        = string
  description = "The folder to run sourcegraph_amp in."
  default     = "/home/coder"
}

variable "install_sourcegraph_amp" {
  type        = bool
  description = "Whether to install sourcegraph-amp."
  default     = true
}

variable "sourcegraph_amp_api_key" {
  type        = string
  description = "sourcegraph-amp API Key"
  default     = ""
}

resource "coder_env" "sourcegraph_amp_api_key" {
  agent_id = var.agent_id
  name     = "SOURCEGRAPH_AMP_API_KEY"
  value    = var.sourcegraph_amp_api_key
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

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing sourcegraph_amp"
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing sourcegraph_amp."
  default     = null
}

variable "base_amp_config" {
  type        = string
  description = <<-EOT
    Base AMP configuration in JSON format. Can be overridden to customize AMP settings.
    
    If empty, defaults enable thinking and todos for autonomous operation. Additional options include:
    - "amp.permissions": [] (tool permissions)
    - "amp.tools.stopTimeout": 600 (extend timeout for long operations)
    - "amp.terminal.commands.nodeSpawn.loadProfile": "daily" (environment loading)
    - "amp.tools.disable": ["builtin:open"] (disable tools for containers)
    - "amp.git.commit.ampThread.enabled": true (link commits to threads)
    - "amp.git.commit.coauthor.enabled": true (add Amp as co-author)
    
    Reference: https://ampcode.com/manual
  EOT
  default     = ""
}

variable "additional_mcp_servers" {
  type        = string
  description = "Additional MCP servers configuration in JSON format to append to amp.mcpServers."
  default     = null
}

locals {
  app_slug = "amp"

  default_base_config = {
    "amp.anthropic.thinking.enabled" = true
    "amp.todos.enabled"              = true
  }

  # Use provided config or default, then extract base settings (excluding mcpServers)
  user_config       = var.base_amp_config != "" ? jsondecode(var.base_amp_config) : local.default_base_config
  base_amp_settings = { for k, v in local.user_config : k => v if k != "amp.mcpServers" }

  coder_mcp = {
    "coder" = {
      "command" = "coder"
      "args"    = ["exp", "mcp", "server"]
      "env" = {
        "CODER_MCP_APP_STATUS_SLUG" = local.app_slug
        "CODER_MCP_AI_AGENTAPI_URL" = "http://localhost:3284"
      }
      "type" = "stdio"
    }
  }

  additional_mcp = var.additional_mcp_servers != null ? jsondecode(var.additional_mcp_servers) : {}

  merged_mcp_servers = merge(
    lookup(local.user_config, "amp.mcpServers", {}),
    local.coder_mcp,
    local.additional_mcp
  )

  final_config = merge(local.base_amp_settings, {
    "amp.mcpServers" = local.merged_mcp_servers
  })

  install_script  = file("${path.module}/scripts/install.sh")
  start_script    = file("${path.module}/scripts/start.sh")
  module_dir_name = ".sourcegraph-amp-module"
}

module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "1.0.1"

  agent_id             = var.agent_id
  web_app_slug         = local.app_slug
  web_app_order        = var.order
  web_app_group        = var.group
  web_app_icon         = var.icon
  web_app_display_name = "Sourcegraph Amp"
  cli_app_slug         = "${local.app_slug}-cli"
  cli_app_display_name = "Sourcegraph Amp CLI"
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
     SOURCEGRAPH_AMP_API_KEY='${var.sourcegraph_amp_api_key}' \
     SOURCEGRAPH_AMP_START_DIRECTORY='${var.folder}' \
     /tmp/start.sh
   EOT

  install_script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh
    ARG_INSTALL_SOURCEGRAPH_AMP='${var.install_sourcegraph_amp}' \
    SOURCEGRAPH_AMP_START_DIRECTORY='${var.folder}' \
    ARG_AMP_CONFIG="$(echo -n '${base64encode(jsonencode(local.final_config))}' | base64 -d)" \
    /tmp/install.sh
  EOT
}


