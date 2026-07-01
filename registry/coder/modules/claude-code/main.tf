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
  default     = "/icon/claude.svg"
}

variable "workdir" {
  type        = string
  description = "Optional project directory. When set, the module pre-creates it if missing and pre-accepts the Claude Code trust/onboarding prompt for it in ~/.claude.json."
  default     = null
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Claude Code. Can be used for dependency ordering between modules (e.g., waiting for git-clone to complete before Claude Code initialization)."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Claude Code."
  default     = null
}

variable "install_claude_code" {
  type        = bool
  description = "Whether to install Claude Code."
  default     = true
}

variable "claude_code_version" {
  type        = string
  description = "The version of Claude Code to install."
  default     = "latest"
}

variable "disable_autoupdater" {
  type        = bool
  description = "Disable Claude Code automatic updates. When true, Claude Code will stay on the installed version."
  default     = false
}

variable "anthropic_api_key" {
  type        = string
  description = "API key passed to Claude Code via the ANTHROPIC_API_KEY env var."
  default     = ""
}

variable "model" {
  type        = string
  description = "Sets the default model for Claude Code via ANTHROPIC_MODEL env var. If empty, Claude Code uses its default. Supports aliases (sonnet, opus) or full model names."
  default     = ""
}

variable "mcp" {
  type        = string
  description = "JSON-encoded string of MCP server configurations. When set, servers are added at Claude Code's user scope so they are available across every project the workspace owner opens."
  default     = ""
}

variable "mcp_config_remote_path" {
  type        = list(string)
  description = "List of URLs that return JSON MCP server configurations (text/plain with valid JSON). Servers are added at Claude Code's user scope."
  default     = []
}

variable "claude_code_oauth_token" {
  type        = string
  description = "OAuth token passed to Claude Code via the CLAUDE_CODE_OAUTH_TOKEN env var. Generate one with `claude setup-token`."
  sensitive   = true
  default     = ""
}

variable "claude_binary_path" {
  type        = string
  description = "Directory where the Claude Code binary is located. Use this if Claude is pre-installed or installed outside the module to a non-default location."
  default     = "$HOME/.local/bin"

  validation {
    condition     = var.claude_binary_path == "$HOME/.local/bin" || !var.install_claude_code
    error_message = "Custom claude_binary_path can only be used when install_claude_code is false. The official installer always installs to $HOME/.local/bin and does not support custom paths."
  }
}

variable "managed_settings" {
  type        = any
  description = "Policy settings written to /etc/claude-code/managed-settings.d/10-coder.json. Highest-precedence client config; works with any inference backend (Anthropic API, Bedrock, Vertex, AI Gateway). See https://docs.anthropic.com/en/docs/claude-code/settings for the schema."
  default     = null
}

variable "enable_ai_gateway" {
  type        = bool
  description = "Use AI Gateway for Claude Code. https://coder.com/docs/ai-coder/ai-gateway"
  default     = false

  validation {
    condition     = !(var.enable_ai_gateway && length(var.anthropic_api_key) > 0)
    error_message = "anthropic_api_key cannot be provided when enable_ai_gateway is true. AI Gateway automatically authenticates the client using Coder credentials."
  }

  validation {
    condition     = !(var.enable_ai_gateway && length(var.claude_code_oauth_token) > 0)
    error_message = "claude_code_oauth_token cannot be provided when enable_ai_gateway is true. AI Gateway automatically authenticates the client using Coder credentials."
  }
}

variable "telemetry" {
  type = object({
    enabled             = optional(bool, false)
    otlp_endpoint       = optional(string, "")
    otlp_protocol       = optional(string, "http/protobuf")
    otlp_headers        = optional(map(string), {})
    resource_attributes = optional(map(string), {})
  })
  default     = {}
  description = "Configure Claude Code OpenTelemetry export. When enabled, sets CLAUDE_CODE_ENABLE_TELEMETRY and the standard OTEL_EXPORTER_OTLP_* environment variables. Coder workspace identifiers (coder.workspace_id, coder.workspace_name, coder.workspace_owner, coder.template_name) are automatically appended to OTEL_RESOURCE_ATTRIBUTES so Claude Code telemetry can be joined with Coder audit and exectrace logs."
}

variable "anthropic_base_url" {
  type        = string
  description = "Override the Anthropic API base URL (sets ANTHROPIC_BASE_URL). Use for self-hosted gateways or proxies that speak the Anthropic Messages API. Mutually exclusive with enable_ai_gateway, which sets ANTHROPIC_BASE_URL to the Coder AI Gateway endpoint."
  default     = ""

  validation {
    condition     = !(var.anthropic_base_url != "" && var.enable_ai_gateway)
    error_message = "anthropic_base_url cannot be provided when enable_ai_gateway is true. AI Gateway sets ANTHROPIC_BASE_URL automatically."
  }
}

variable "use_bedrock" {
  type        = bool
  description = "Run Claude Code against Amazon Bedrock (sets CLAUDE_CODE_USE_BEDROCK=1). Authentication uses the workspace's AWS credential chain (IRSA, instance profile, or AWS_* env vars). Mutually exclusive with enable_ai_gateway and use_vertex."
  default     = false

  validation {
    condition     = !(var.use_bedrock && var.enable_ai_gateway)
    error_message = "use_bedrock cannot be combined with enable_ai_gateway."
  }

  validation {
    condition     = !(var.use_bedrock && var.use_vertex)
    error_message = "use_bedrock cannot be combined with use_vertex. Choose at most one provider backend."
  }
}

variable "use_vertex" {
  type        = bool
  description = "Run Claude Code against Google Vertex AI (sets CLAUDE_CODE_USE_VERTEX=1). Authentication uses Google Application Default Credentials inside the workspace. Mutually exclusive with enable_ai_gateway and use_bedrock."
  default     = false

  validation {
    condition     = !(var.use_vertex && var.enable_ai_gateway)
    error_message = "use_vertex cannot be combined with enable_ai_gateway."
  }
}

resource "coder_env" "claude_code_oauth_token" {
  count    = var.claude_code_oauth_token != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "CLAUDE_CODE_OAUTH_TOKEN"
  value    = var.claude_code_oauth_token
}

resource "coder_env" "anthropic_api_key" {
  count    = var.anthropic_api_key != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "ANTHROPIC_API_KEY"
  value    = var.anthropic_api_key
}

# ANTHROPIC_AUTH_TOKEN authenticates the client against Coder's AI Gateway
# using the workspace owner's session token, per the AI Gateway docs.
resource "coder_env" "anthropic_auth_token" {
  count    = var.enable_ai_gateway ? 1 : 0
  agent_id = var.agent_id
  name     = "ANTHROPIC_AUTH_TOKEN"
  value    = data.coder_workspace_owner.me.session_token
}

resource "coder_env" "disable_autoupdater" {
  count    = var.disable_autoupdater ? 1 : 0
  agent_id = var.agent_id
  name     = "DISABLE_AUTOUPDATER"
  value    = "1"
}


resource "coder_env" "anthropic_model" {
  count    = var.model != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "ANTHROPIC_MODEL"
  value    = var.model
}

resource "coder_env" "anthropic_base_url" {
  count    = var.enable_ai_gateway || var.anthropic_base_url != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "ANTHROPIC_BASE_URL"
  value    = var.enable_ai_gateway ? "${data.coder_workspace.me.access_url}/api/v2/aibridge/anthropic" : var.anthropic_base_url
}

resource "coder_env" "use_bedrock" {
  count    = var.use_bedrock ? 1 : 0
  agent_id = var.agent_id
  name     = "CLAUDE_CODE_USE_BEDROCK"
  value    = "1"
}

resource "coder_env" "use_vertex" {
  count    = var.use_vertex ? 1 : 0
  agent_id = var.agent_id
  name     = "CLAUDE_CODE_USE_VERTEX"
  value    = "1"
}

locals {
  # Always inject Coder workspace identifiers so OTEL data can be joined with
  # Coder's audit log / exectrace on workspace_id without per-template wiring.
  otel_resource_attributes = merge(
    var.telemetry.resource_attributes,
    {
      "coder.workspace_id"       = data.coder_workspace.me.id
      "coder.workspace_name"     = data.coder_workspace.me.name
      "coder.workspace_owner"    = data.coder_workspace_owner.me.name
      "coder.workspace_owner_id" = data.coder_workspace_owner.me.id
      "coder.template_name"      = data.coder_workspace.me.template_name
      "coder.template_version"   = data.coder_workspace.me.template_version
      "coder.access_url"         = data.coder_workspace.me.access_url
    },
  )
}

resource "coder_env" "claude_code_enable_telemetry" {
  count    = var.telemetry.enabled ? 1 : 0
  agent_id = var.agent_id
  name     = "CLAUDE_CODE_ENABLE_TELEMETRY"
  value    = "1"
}

resource "coder_env" "otel_exporter_otlp_endpoint" {
  count    = var.telemetry.enabled && var.telemetry.otlp_endpoint != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "OTEL_EXPORTER_OTLP_ENDPOINT"
  value    = var.telemetry.otlp_endpoint
}

resource "coder_env" "otel_exporter_otlp_protocol" {
  count    = var.telemetry.enabled ? 1 : 0
  agent_id = var.agent_id
  name     = "OTEL_EXPORTER_OTLP_PROTOCOL"
  value    = var.telemetry.otlp_protocol
}

resource "coder_env" "otel_exporter_otlp_headers" {
  count    = var.telemetry.enabled && length(var.telemetry.otlp_headers) > 0 ? 1 : 0
  agent_id = var.agent_id
  name     = "OTEL_EXPORTER_OTLP_HEADERS"
  value    = join(",", [for k, v in var.telemetry.otlp_headers : "${k}=${v}"])
}

resource "coder_env" "otel_resource_attributes" {
  count    = var.telemetry.enabled ? 1 : 0
  agent_id = var.agent_id
  name     = "OTEL_RESOURCE_ATTRIBUTES"
  value    = join(",", [for k, v in local.otel_resource_attributes : "${k}=${v}"])
}

locals {
  workdir = var.workdir != null ? trimsuffix(var.workdir, "/") : ""
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_CLAUDE_CODE_VERSION    = var.claude_code_version
    ARG_INSTALL_CLAUDE_CODE    = tostring(var.install_claude_code)
    ARG_CLAUDE_BINARY_PATH     = var.claude_binary_path
    ARG_WORKDIR                = local.workdir
    ARG_MCP                    = var.mcp != "" ? base64encode(var.mcp) : ""
    ARG_MCP_CONFIG_REMOTE_PATH = base64encode(jsonencode(var.mcp_config_remote_path))
    ARG_ENABLE_AI_GATEWAY      = tostring(var.enable_ai_gateway)
    ARG_MANAGED_SETTINGS_JSON  = var.managed_settings != null ? base64encode(jsonencode(var.managed_settings)) : ""
    ARG_USE_BEDROCK            = tostring(var.use_bedrock)
    ARG_USE_VERTEX             = tostring(var.use_vertex)
    ARG_ANTHROPIC_BASE_URL     = var.anthropic_base_url
  })
  module_dir_name = ".coder-modules/coder/claude-code"
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/${local.module_dir_name}"
  display_name_prefix = "Claude Code"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
}

# Pass-through of coder-utils script outputs so upstream modules can serialize
# their coder_script resources behind this module's install pipeline using
# `coder exp sync want <self> <each name>`.
output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module actually creates, in run order (pre_install, install, post_install). Scripts that were not configured are absent from the list."
  value       = module.coder_utils.scripts
}
