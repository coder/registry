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
  default     = "/icon/cursor.svg"
}

variable "folder" {
  type        = string
  description = "The folder to run Cursor CLI in."
  default     = "/home/coder"
}

variable "install_cursor_cli" {
  type        = bool
  description = "Whether to install Cursor CLI."
  default     = true
}

variable "cursor_cli_version" {
  type        = string
  description = "The version of Cursor CLI to install (latest for latest)."
  default     = "latest"
}

variable "interactive" {
  type        = bool
  description = "Run in interactive chat mode (default)."
  default     = true
}

variable "initial_prompt" {
  type        = string
  description = "Initial prompt to start the chat with (passed as trailing arg)."
  default     = ""
}

variable "non_interactive_cmd" {
  type        = string
  description = "Additional arguments appended when interactive=false (advanced usage)."
  default     = ""
}

variable "force" {
  type        = bool
  description = "Pass -f/--force to allow commands unless explicitly denied."
  default     = false
}

variable "model" {
  type        = string
  description = "Pass -m/--model to select model (e.g., sonnet-4, gpt-5)."
  default     = ""
}

variable "output_format" {
  type        = string
  description = "Output format with -p: text, json, or stream-json."
  default     = ""
}

variable "api_key" {
  type        = string
  description = "API key (sets CURSOR_API_KEY env or pass via -a)."
  default     = ""
  sensitive   = true
}

variable "extra_args" {
  type        = list(string)
  description = "Additional args to pass to the Cursor CLI."
  default     = []
}

variable "binary_name" {
  type        = string
  description = "Cursor Agent binary name (default: cursor-agent)."
  default     = "cursor-agent"
}

variable "base_command" {
  type        = string
  description = "Base Cursor CLI command to run (default: none for chat)."
  default     = ""
}

variable "additional_settings" {
  type        = string
  description = "JSON to merge into ~/.cursor/settings.json (e.g., mcpServers)."
  default     = ""
}

locals {
  app_slug        = "cursor-cli"
  install_script  = file("${path.module}/scripts/install.sh")
  start_script    = file("${path.module}/scripts/start.sh")
  module_dir_name = ".cursor-cli-module"
}

resource "coder_script" "cursor_cli" {
  agent_id     = var.agent_id
  display_name = "Cursor CLI"
  icon         = var.icon
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/install.sh
    chmod +x /tmp/install.sh
    ARG_INSTALL='${var.install_cursor_cli}' \
    ARG_VERSION='${var.cursor_cli_version}' \
    ADDITIONAL_SETTINGS='${base64encode(replace(var.additional_settings, "'", "'\\''"))}' \
    MODULE_DIR_NAME='${local.module_dir_name}' \
    FOLDER='${var.folder}' \
    /tmp/install.sh | tee "$HOME/${local.module_dir_name}/install.log"

    echo -n '${base64encode(local.start_script)}' | base64 -d > /tmp/start.sh
    chmod +x /tmp/start.sh
    INTERACTIVE='${var.interactive}' \
    INITIAL_PROMPT='${replace(var.initial_prompt, "'", "'\\''")}' \
    NON_INTERACTIVE_CMD='${replace(var.non_interactive_cmd, "'", "'\\''")}' \
    BASE_COMMAND='${var.base_command}' \
    FORCE='${var.force}' \
    MODEL='${var.model}' \
    OUTPUT_FORMAT='${var.output_format}' \
    API_KEY_SECRET='${var.api_key}' \
    EXTRA_ARGS='${base64encode(join("\n", var.extra_args))}' \
    MODULE_DIR_NAME='${local.module_dir_name}' \
    FOLDER='${var.folder}' \
    BINARY_NAME='${var.binary_name}' \
    /tmp/start.sh | tee "$HOME/${local.module_dir_name}/start.log"
  EOT
  run_on_start = true
}

resource "coder_app" "cursor_cli" {
  agent_id     = var.agent_id
  slug         = local.app_slug
  display_name = "Cursor CLI"
  icon         = var.icon
  order        = var.order
  group        = var.group
  command      = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail
    if [ -f "$HOME/${local.module_dir_name}/start.log" ]; then
      tail -n +1 -f "$HOME/${local.module_dir_name}/start.log"
    else
      echo "Cursor CLI not started yet. Check install/start logs in $HOME/${local.module_dir_name}/"
      /bin/bash
    fi
  EOT
}
