terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.12"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

variable "icon" {
  type        = string
  description = "The icon to use for the app."
  default     = "/icon/gemini.svg"
}

variable "workdir" {
  type        = string
  description = "Optional project directory. When set, the module pre-creates it if missing and adds it as a trusted project in Gemini settings."
  default     = null
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

variable "install_gemini" {
  type        = bool
  description = "Whether to install Gemini."
  default     = true
}

variable "gemini_version" {
  type        = string
  description = "The version of Gemini to install."
  default     = "latest"
}

variable "gemini_api_key" {
  type        = string
  description = "Gemini API Key for CLI and API access."
  sensitive   = true
  default     = ""
}

variable "gemini_settings_json" {
  type        = string
  description = "JSON to use in ~/.gemini/settings.json. If empty, a default is generated."
  default     = ""
}

variable "use_vertexai" {
  type        = bool
  description = "Whether to use Vertex AI."
  default     = false
}

variable "gemini_model" {
  type        = string
  description = "The model to use for Gemini (e.g., gemini-2.5-pro)."
  default     = ""
}

variable "additional_extensions" {
  type        = string
  description = "Additional extensions configuration in JSON format to append to the config."
  default     = null
}

resource "coder_env" "gemini_api_key" {
  count    = var.gemini_api_key != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "GEMINI_API_KEY"
  value    = var.gemini_api_key
}

resource "coder_env" "google_api_key" {
  count    = var.gemini_api_key != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "GOOGLE_API_KEY"
  value    = var.gemini_api_key
}

resource "coder_env" "gemini_use_vertex_ai" {
  count    = var.use_vertexai ? 1 : 0
  agent_id = var.agent_id
  name     = "GOOGLE_GENAI_USE_VERTEXAI"
  value    = var.use_vertexai
}

resource "coder_env" "gemini_model" {
  count    = var.gemini_model != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "GEMINI_MODEL"
  value    = var.gemini_model
}


locals {
  base_extensions = <<-EOT
{
  "coder": {
    "command": "coder",
    "args": [
      "exp",
      "mcp",
      "server"
    ],
    "env": {
      "CODER_MCP_APP_STATUS_SLUG": "gemini",
      "CODER_MCP_AI_AGENTAPI_URL": "http://localhost:3284"
    }
  }
}
EOT

  workdir = var.workdir != null ? trimsuffix(var.workdir, "/") : ""
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL_GEMINI        = tostring(var.install_gemini)
    ARG_GEMINI_VERSION        = var.gemini_version != "" ? base64encode(var.gemini_version) : ""
    ARG_GEMINI_CONFIG         = var.gemini_settings_json != "" ? base64encode(var.gemini_settings_json) : ""
    ARG_ADDITIONAL_EXTENSIONS = var.additional_extensions != null ? base64encode(var.additional_extensions) : ""
    ARG_BASE_EXTENSIONS       = base64encode(local.base_extensions)
    ARG_WORKDIR               = local.workdir != "" ? base64encode(local.workdir) : ""
  })
  module_dir_name = ".coder-modules/coder-labs/gemini"
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/${local.module_dir_name}"
  display_name_prefix = "Gemini"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
}


output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module creates, in run order (pre_install, install, post_install). Scripts that were not configured are absent from the list."
  value       = module.coder_utils.scripts
}
