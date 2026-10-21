terraform {
  required_version = ">= 1.3"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
    }
  }
}

variable "agent_id" {
  description = "The ID of the Coder agent whose MCP clients are configured."
  type        = string
}

variable "clients" {
  description = "MCP clients to configure in the workspace."
  type        = set(string)

  validation {
    condition = length(var.clients) > 0 && alltrue([
      for client in var.clients : contains([
        "claude code",
        "codex",
        "continue",
        "copilot cli",
        "cursor",
        "gemini",
        "goose",
        "opencode",
        "vscode",
        "windsurf",
      ], client)
    ])
    error_message = "clients must contain at least one client supported by mcp-add."
  }
}

variable "default" {
  description = "MCP servers selected by default."
  type        = set(string)
  default     = []

  validation {
    condition = alltrue([
      for server in var.default : contains(["github", "playwright"], server)
    ])
    error_message = "default can contain only github and playwright."
  }
}

variable "github_auth" {
  description = "Authentication used for the GitHub MCP server. token-env reads a workspace environment variable, external-auth resolves a Coder provider at connection time, and native-oauth uses the pinned official local server image."
  type = object({
    mode                = optional(string, "none")
    token_env_var       = optional(string, "GITHUB_MCP_TOKEN")
    external_auth_id    = optional(string, "github")
    oauth_callback_port = optional(number, 8085)
    local_server_image  = optional(string, "ghcr.io/github/github-mcp-server:v1.11.0@sha256:fbec75de11c255213fa08d80fb166abe73d851fff631c51c0079872967720699")
  })
  default = {}

  validation {
    condition     = contains(["none", "token-env", "external-auth", "native-oauth"], var.github_auth.mode)
    error_message = "github_auth.mode must be one of none, token-env, external-auth, or native-oauth."
  }

  validation {
    condition     = var.github_auth.mode != "token-env" || can(regex("^[A-Za-z_][A-Za-z0-9_]*$", var.github_auth.token_env_var))
    error_message = "github_auth.token_env_var must be a valid environment variable name."
  }

  validation {
    condition     = var.github_auth.mode != "external-auth" || can(regex("^[A-Za-z0-9][A-Za-z0-9._-]*$", var.github_auth.external_auth_id))
    error_message = "github_auth.external_auth_id must be a non-empty Coder provider identifier."
  }

  validation {
    condition     = var.github_auth.mode != "native-oauth" || (var.github_auth.oauth_callback_port >= 1024 && var.github_auth.oauth_callback_port <= 65535 && floor(var.github_auth.oauth_callback_port) == var.github_auth.oauth_callback_port)
    error_message = "github_auth.oauth_callback_port must be an integer between 1024 and 65535."
  }

  validation {
    condition     = var.github_auth.mode != "native-oauth" || can(regex("^ghcr\\.io/github/github-mcp-server:v[0-9]+\\.[0-9]+\\.[0-9]+@sha256:[0-9a-f]{64}$", var.github_auth.local_server_image))
    error_message = "github_auth.local_server_image must pin an official versioned GitHub MCP image by sha256 digest."
  }
}

variable "coder_parameter_order" {
  description = "The order of the MCP server field in the workspace creation form."
  type        = number
  default     = null
}

variable "mcp_add_version" {
  description = "The pinned mcp-add version used to configure selected clients."
  type        = string
  default     = "0.2.4"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.mcp_add_version))
    error_message = "mcp_add_version must be an exact semantic version such as 0.2.4."
  }
}

variable "node_version" {
  description = "The pinned Node.js version bootstrapped when the workspace does not provide Node.js 18 or newer with npx."
  type        = string
  default     = "22.23.2"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.node_version))
    error_message = "node_version must be an exact semantic version such as 22.23.2."
  }
}

variable "playwright_mcp_version" {
  description = "The pinned Playwright MCP server version written to client configurations."
  type        = string
  default     = "0.0.79"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.playwright_mcp_version))
    error_message = "playwright_mcp_version must be an exact semantic version such as 0.0.79."
  }
}

locals {
  servers = {
    github = {
      name        = "GitHub"
      description = "Repository, issue, pull request, and code workflow tools."
    }
    playwright = {
      name        = "Playwright"
      description = "Browser automation and web application testing tools."
    }
  }

  selected_servers = sort(tolist(toset(jsondecode(data.coder_parameter.mcp_servers.value))))
  github_auth_clients = {
    "token-env"     = toset(["claude code", "codex", "cursor"])
    "external-auth" = toset(["claude code"])
    "native-oauth"  = var.clients
    "none"          = var.clients
  }
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_CLIENTS                = base64encode(join(",", sort(tolist(var.clients))))
    ARG_MCP_ADD_VERSION        = var.mcp_add_version
    ARG_NODE_VERSION           = var.node_version
    ARG_PLAYWRIGHT_MCP_VERSION = var.playwright_mcp_version
    ARG_SELECTED_SERVERS       = base64encode(join(",", local.selected_servers))
  })
  auth_script = contains(local.selected_servers, "github") && var.github_auth.mode != "none" ? templatefile("${path.module}/scripts/auth.sh.tftpl", {
    ARG_AUTH_MODE           = var.github_auth.mode
    ARG_CLIENTS             = base64encode(join(",", sort(tolist(var.clients))))
    ARG_EXTERNAL_AUTH_ID    = base64encode(var.github_auth.external_auth_id)
    ARG_IS_PREBUILD         = tostring(lower(data.coder_workspace_owner.me.name) == "prebuilds")
    ARG_LOCAL_SERVER_IMAGE  = base64encode(var.github_auth.local_server_image)
    ARG_MCP_ADD_VERSION     = var.mcp_add_version
    ARG_OAUTH_CALLBACK_PORT = tostring(var.github_auth.oauth_callback_port)
    ARG_TOKEN_ENV_VAR       = base64encode(var.github_auth.token_env_var)
  }) : null
}

data "coder_workspace_owner" "me" {}

data "coder_parameter" "mcp_servers" {
  name         = "mcp_servers"
  display_name = "MCP Servers"
  description  = "Select official MCP servers to configure for your workspace agents."
  type         = "list(string)"
  form_type    = "multi-select" # requires Coder version 2.24+
  default      = jsonencode(sort(tolist(var.default)))
  mutable      = false
  order        = var.coder_parameter_order

  lifecycle {
    precondition {
      condition     = var.github_auth.mode == "none" || length(setsubtract(var.clients, local.github_auth_clients[var.github_auth.mode])) == 0
      error_message = "github_auth.mode ${var.github_auth.mode} does not support every selected client. token-env supports Claude Code, Codex, and Cursor; external-auth supports Claude Code only; native-oauth supports all configured clients through the local stdio server."
    }
  }

  dynamic "option" {
    for_each = local.servers
    content {
      name        = option.value.name
      description = option.value.description
      value       = option.key
    }
  }
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/.coder-modules/coder-labs/mcp-servers"
  display_name_prefix = "MCP Servers"
  icon                = "/icon/mcp.svg"
  install_script      = local.install_script
  post_install_script = local.auth_script
}

output "selected_servers" {
  description = "MCP server identifiers selected in the workspace creation form."
  value       = local.selected_servers
}

output "scripts" {
  description = "Ordered list of coder exp sync names produced by this module."
  value       = module.coder_utils.scripts
}
