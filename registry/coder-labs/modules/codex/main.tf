terraform {
  required_version = ">= 1.9"

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
  default     = "/icon/openai.svg"
}

variable "workdir" {
  type        = string
  description = "Optional project directory. When set, the module pre-creates it if missing and adds it as a trusted project in Codex config.toml."
  default     = null
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Codex."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Codex."
  default     = null
}

variable "install_codex" {
  type        = bool
  description = "Whether to install Codex."
  default     = true
}

variable "codex_version" {
  type        = string
  description = "The version of Codex to install."
  default     = ""
}

variable "openai_api_key" {
  type        = string
  description = "OpenAI API key for Codex CLI."
  default     = ""
}

variable "base_config_toml" {
  type        = string
  description = <<-EOT
    Complete base TOML configuration for Codex (without mcp_servers section).
    When empty, the module generates a minimal default:

      preferred_auth_method = "apikey"
      # model_provider = "aibridge"           (sets the default profile, when enable_ai_gateway = true)
      # model_reasoning_effort = "<value>"    (sets the reasoning effort, when model_reasoning_effort is set)

      [projects."<workdir>"]                  (when workdir is set)
      trust_level = "trusted"

    When non-empty, the value is written verbatim as the base of config.toml;
    additional_mcp_servers and AI Gateway sections are still appended after it.
  EOT
  default     = ""
}

variable "additional_mcp_servers" {
  type        = string
  description = "Additional MCP servers configuration in TOML format."
  default     = ""
}

variable "model_reasoning_effort" {
  type        = string
  description = "The reasoning effort for the model."
  default     = ""
  validation {
    condition     = contains(["", "none", "minimal", "low", "medium", "high", "xhigh"], var.model_reasoning_effort)
    error_message = "model_reasoning_effort must be one of: none, minimal, low, medium, high, xhigh."
  }
}

variable "enable_ai_gateway" {
  type        = bool
  description = "Use AI Gateway for Codex. https://coder.com/docs/ai-coder/ai-gateway"
  default     = false

  validation {
    condition     = !(var.enable_ai_gateway && length(var.openai_api_key) > 0)
    error_message = "openai_api_key cannot be provided when enable_ai_gateway is true. AI Gateway automatically authenticates the client using Coder credentials."
  }
}

resource "coder_env" "openai_api_key" {
  count    = var.openai_api_key != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "OPENAI_API_KEY"
  value    = var.openai_api_key
}

# Authenticates the client against Coder's AI Gateway using the workspace
# owner's session token. Referenced by config.toml model_providers.aibridge.
resource "coder_env" "ai_gateway_session_token" {
  count    = var.enable_ai_gateway ? 1 : 0
  agent_id = var.agent_id
  name     = "CODER_AIBRIDGE_SESSION_TOKEN"
  value    = data.coder_workspace_owner.me.session_token
}

locals {
  workdir         = var.workdir != null ? trimsuffix(var.workdir, "/") : ""
  aibridge_config = <<-EOF
  [model_providers.aibridge]
  name = "AI Bridge"
  base_url = "${data.coder_workspace.me.access_url}/api/v2/aibridge/openai/v1"
  env_key = "CODER_AIBRIDGE_SESSION_TOKEN"
  wire_api = "responses"

  EOF
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL                = tostring(var.install_codex)
    ARG_CODEX_VERSION          = var.codex_version
    ARG_WORKDIR                = local.workdir
    ARG_BASE_CONFIG_TOML       = var.base_config_toml != "" ? base64encode(var.base_config_toml) : ""
    ARG_ADDITIONAL_MCP_SERVERS = var.additional_mcp_servers != "" ? base64encode(var.additional_mcp_servers) : ""
    ARG_ENABLE_AI_GATEWAY      = tostring(var.enable_ai_gateway)
    ARG_AIBRIDGE_CONFIG        = var.enable_ai_gateway ? base64encode(local.aibridge_config) : ""
    ARG_MODEL_REASONING_EFFORT = var.model_reasoning_effort
  })
  module_dir_name = ".coder-modules/coder-labs/codex"
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/${local.module_dir_name}"
  display_name_prefix = "Codex"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
}

output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module creates, in run order (pre_install, install, post_install). Scripts that were not configured are absent from the list."
  value       = module.coder_utils.scripts
}
