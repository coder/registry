terraform {
  required_version = ">= 1.9"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
    aap = {
      source  = "ansible/aap"
      version = "1.3.0"
    }
  }
}

locals {
  # A built-in icon like "/icon/code.svg" or a full URL of icon
  icon_url = "https://raw.githubusercontent.com/coder/coder/main/site/static/icon/code.svg"
  # a map of all possible values
  options = {
    "Option 1" = {
      "name"  = "Option 1",
      "value" = "1"
      "icon"  = "/emojis/1.png"
    }
    "Option 2" = {
      "name"  = "Option 2",
      "value" = "2"
      "icon"  = "/emojis/2.png"
    }
  }
}

# Add required variables for your modules and remove any unneeded variables
variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "agent_module_ref" {
  type = object({
    agent_ref         = string
    agent_module_dir  = string
    agent_binary_path = string
  })
}

variable "agent_parameters" {
  type = object({
    claude_code = optional(object({
      resume_session_id            = optional(string, "")
      continue                     = optional(bool, false)
      dangerously_skip_permissions = optional(bool, false)
      permission_mode              = optional(string, "")
    }), null)

    another_agent = optional(object({
      temperature   = optional(number, null)
      system_prompt = optional(string, null)
    }), null)
  })
  default = {}

  validation {
    condition     = var.agent_parameters.claude_code == null || var.agent_module_ref.agent_name == "claude_code"
    error_message = "'claude_code' parameters are only valid when ref is 'claude-code'."
  }

  validation {
    condition     = var.agent_parameters.another_agent == null || var.agent_module_ref.agent_name == "another_agent"
    error_message = "'another_agent' parameters are only valid when ref is 'another_agent'."
  }
}

variable "enable_agentapi" {
  type        = bool
  description = "Whether to enable AgentAPI for this agent. If false, the AgentAPI module will not be included, the start script will still run and a cli app will be created which runs the agent in normal terminal mode"
}

variable "agentapi" {
  description = <<-EOT
    AgentAPI app configuration:
    - `web_app`: Whether to create the web app for Claude Code. When false, AgentAPI still runs but no web UI app icon is shown in the Coder dashboard. This is automatically enabled when using Coder Tasks, regardless of this setting.
    - `cli_app`: Whether to create a CLI app for Claude Code.
    - `web_app_display_name`: Display name for the web app.
    - `cli_app_display_name`: Display name for the CLI app.
    - `web_app_icon`: The icon to use for the app.
  EOT
  type = object({
    version              = optional(string, "latest")
    web_app              = optional(bool, true)
    cli_app              = optional(bool, false)
    web_app_display_name = optional(string, "ClaudeCode")
    cli_app_display_name = optional(string, "ClaudeCode CLI")
    web_app_icon         = optional(string, "/icon/claude.svg")
    module_directory     = optional(string)
  })
  default = {}
}

variable "cli_app_display_name" {
  type        = string
  description = "Display name for the CLI app. Only applicable if `enable_agentapi` is false."
  default     = "Agent CLI"

  validation {
    condition     = var.enable_agentapi == false
    error_message = "cli_app_display_name should not be set when enable_agentapi is true."
  }
}

variable "enable_boundary" {
  type        = bool
  description = "Whether to enable Boundary for this agent. If false, the Boundary module will not be included and Boundary will not be installed, but the start script will still run."
  default     = false
}

variable "boundary_wrapper_path" {
  type        = string
  description = "Path to the Boundary CLI wrapper script. Only applicable if `enable_boundary` is true."
  default     = ""

  validation {
    condition     = var.enable_boundary == false || (var.enable_boundary == true && var.boundary_wrapper_path != "")
    error_message = "boundary_wrapper_path must be set when enable_boundary is true."
  }
}

locals {
  start_script           = file("${path.module}/${var.agent_module_ref.agent_name}_start.sh")
  export_variable_prefix = upper(var.agent_module_ref.agent_name)

  export_variables = {
    for key, value in var.agent_parameters[var.agent_module_ref.agent_name] : "${local.export_variable_prefix}_${upper(key)}" => value
  }

  export_merged_variables = merge(local.export_variables, {
    "ARG_ENABLE_AGENTAPI"       = var.enable_agentapi
    "ARG_ENABLE_BOUNDARY"       = var.enable_boundary
    "ARG_BOUNDARY_WRAPPER_PATH" = var.boundary_wrapper_path
  })

  default_app_slugs = {
    "claude_code" = "ccw"
  }

  app_slug     = lookup(local.default_app_slugs, var.agent_module_ref.agent_name)
  cli_app_slug = "${local.app_slug}-cli"

}

variable "ai_prompt" {
  type        = string
  description = "Initial task prompt for Claude Code."
  default     = ""
}

resource "coder_script" "start_script" {
  agent_id     = var.agent_id
  display_name = "Task Statrt Script"
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.start_script)}' | base64 -d > "${var.agent_module_ref.agent_module_dir}/start.sh"

    # Export variables for the script based on the provided agent parameters
    %{for var_name, var_value in local.export_merged_variables~}
    export ${var_name}="${var_value}"
    %{endfor~}
    chmod +x "${var.agent_module_ref.agent_module_dir}/start.sh"
    "${var.agent_module_ref.agent_module_dir}/start.sh"
  EOT
}

module "agentapi" {
  count = var.enable_agentapi ? 1 : 0

  source               = "git::https://github.com/coder/registry.git//registry/coder/modules/agentapi?ref=35C4n0r/refactor-agentapi-decouple"
  agentapi_version     = var.agentapi.version
  agent_id             = var.agent_id
  cli_app              = var.agentapi.cli_app
  cli_app_display_name = var.agentapi.cli_app_display_name
  cli_app_slug         = local.cli_app_slug
  web_app              = var.agentapi.web_app
  web_app_display_name = var.agentapi.web_app_display_name
  web_app_icon         = var.agentapi.web_app_icon
  web_app_slug         = local.app_slug
  module_directory     = var.agentapi.module_directory
}

resource "coder_app" "non_agentapi_cli" {
  count = var.enable_agentapi ? 0 : 1

  agent_id     = var.agent_id
  display_name = var.cli_app_display_name
  command      = ""
  slug         = local.cli_app_slug
}

output "task_app_id" {
  description = "The app ID for the task's web app, if created."
  value       = try(module.agentapi[0].task_app_id, coder_app.non_agentapi_cli[0].id)
}
