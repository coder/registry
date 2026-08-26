terraform {
  required_version = ">= 1.0"

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
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_CLIENTS                = base64encode(join(",", sort(tolist(var.clients))))
    ARG_MCP_ADD_VERSION        = var.mcp_add_version
    ARG_NODE_VERSION           = var.node_version
    ARG_PLAYWRIGHT_MCP_VERSION = var.playwright_mcp_version
    ARG_SELECTED_SERVERS       = base64encode(join(",", local.selected_servers))
  })
}

data "coder_parameter" "mcp_servers" {
  name         = "mcp_servers"
  display_name = "MCP Servers"
  description  = "Select official MCP servers to configure for your workspace agents."
  type         = "list(string)"
  form_type    = "multi-select" # requires Coder version 2.24+
  default      = jsonencode(sort(tolist(var.default)))
  mutable      = false
  order        = var.coder_parameter_order

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
  module_directory    = "$HOME/.coder-modules/coder/mcp-servers"
  display_name_prefix = "MCP Servers"
  icon                = "/icon/mcp.svg"
  install_script      = local.install_script
}

output "selected_servers" {
  description = "MCP server identifiers selected in the workspace creation form."
  value       = local.selected_servers
}

output "scripts" {
  description = "Ordered list of coder exp sync names produced by this module."
  value       = module.coder_utils.scripts
}
