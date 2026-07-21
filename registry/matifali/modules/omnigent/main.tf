terraform {
  required_version = ">= 1.9"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
    }
  }
}

variable "agent_id" {
  description = "The ID of a Coder agent."
  type        = string
}

variable "icon" {
  description = "Icon for Omnigent scripts and app."
  type        = string
  default     = "/icon/omnigent.svg"
}

variable "port" {
  description = "Port the Omnigent server listens on inside the workspace."
  type        = number
  default     = 6767
  validation {
    condition     = var.port > 1024 && var.port < 65536
    error_message = "port must be between 1025 and 65535."
  }
}

variable "allowed_origins" {
  description = "Additional trusted browser origins for Omnigent HTTP/WebSocket CSRF checks. Use this when exposing Omnigent through a reverse proxy not covered by the automatic Coder app origin detection."
  type        = list(string)
  default     = []
  validation {
    condition = alltrue([
      for origin in var.allowed_origins : trimspace(origin) == origin && can(regex("^https?://[^/?#,[:space:]]+$", origin))
    ])
    error_message = "allowed_origins entries must be origins like https://omnigent.example.com (scheme, host, optional port; no path)."
  }
}

variable "omnigent_version" {
  description = "Omnigent version to install. 'latest' installs the newest release."
  type        = string
  default     = "latest"
}

variable "share" {
  description = "Coder app share level."
  type        = string
  default     = "owner"
  validation {
    condition     = contains(["owner", "authenticated", "public"], var.share)
    error_message = "share must be one of: owner, authenticated, public."
  }
}

variable "order" {
  description = "Order for the Omnigent app in the Coder UI."
  type        = number
  default     = null
}

variable "server_config" {
  description = "Inline server_config.yaml content for the Omnigent server. Supports policies, policy_modules, admins, and allowed_domains keys. When set, written to the module directory and passed as -c to the server. Mutually exclusive with server_config_path."
  type        = string
  default     = null
  validation {
    condition     = !(var.server_config != null && var.server_config_path != null)
    error_message = "Only one of server_config or server_config_path may be set."
  }
}

variable "server_config_path" {
  description = "Path to an existing server_config.yaml in the workspace. When set, passed directly as -c to the server; no config file is written by this module. Mutually exclusive with server_config."
  type        = string
  default     = null
}

variable "agents" {
  description = "Custom agent YAML definitions to pre-register at server startup. Each entry is written to the module directory and passed as --agent flags."
  type = list(object({
    name    = string
    content = string
  }))
  default = []
  validation {
    condition = alltrue([
      for agent in var.agents : (
        length(trimspace(agent.name)) > 0 &&
        !strcontains(agent.name, "\t") &&
        !strcontains(agent.name, "\n") &&
        !strcontains(agent.name, "\r")
      )
    ])
    error_message = "agents entries must have a non-empty name without tab or newline characters."
  }
}

variable "pre_install_script" {
  description = "Custom script to run before installing Omnigent."
  type        = string
  default     = null
}

variable "post_install_script" {
  description = "Custom script to run after installing Omnigent."
  type        = string
  default     = null
}

locals {
  module_dir         = "$HOME/.coder-modules/matifali/omnigent"
  server_config_file = "${local.module_dir}/config/server.yaml"
  agents_dir         = "${local.module_dir}/agents"

  effective_server_config_path = (
    var.server_config_path != null ? var.server_config_path :
    var.server_config != null ? local.server_config_file :
    null
  )

  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_OMNIGENT_VERSION_B64 = var.omnigent_version != "latest" ? base64encode(var.omnigent_version) : ""
    ARG_PORT                 = tostring(var.port)
    ARG_WRITE_SERVER_CONFIG  = tostring(var.server_config != null)
    ARG_SERVER_CONFIG_B64    = var.server_config != null ? base64encode(var.server_config) : ""
    ARG_SERVER_CONFIG_FILE   = local.server_config_file
    ARG_SERVER_CONFIG_DIR    = "${local.module_dir}/config"
    ARG_AGENTS_B64           = length(var.agents) > 0 ? base64encode(join("\n", [for a in var.agents : "${a.name}\t${base64encode(a.content)}"])) : ""
    ARG_AGENTS_DIR           = local.agents_dir
  })

  start_script = templatefile("${path.module}/scripts/start.sh.tftpl", {
    ARG_PORT                         = tostring(var.port)
    ARG_EFFECTIVE_SERVER_CONFIG_PATH = local.effective_server_config_path != null ? local.effective_server_config_path : ""
    ARG_AGENTS_DIR                   = local.agents_dir
    ARG_ALLOWED_ORIGINS_B64          = base64encode(join(",", var.allowed_origins))
  })
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = local.module_dir
  display_name_prefix = "Omnigent"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
  start_script        = local.start_script
}

resource "coder_app" "omnigent" {
  agent_id     = var.agent_id
  slug         = "omnigent"
  display_name = "Omnigent"
  url          = "http://localhost:${var.port}"
  icon         = var.icon
  subdomain    = true
  share        = var.share
  order        = var.order

  healthcheck {
    url       = "http://localhost:${var.port}/health"
    interval  = 15
    threshold = 3
  }
}

output "scripts" {
  description = "Ordered list of coder exp sync names produced by this module, in run order."
  value       = module.coder_utils.scripts
}

output "port" {
  description = "Port the Omnigent server is listening on."
  value       = var.port
}

output "server_config_path" {
  description = "Effective path to the server config file, or empty string if no config is used."
  value       = local.effective_server_config_path != null ? local.effective_server_config_path : ""
}
