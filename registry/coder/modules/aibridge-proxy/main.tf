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

variable "proxy_url" {
  type        = string
  description = "The full URL of the AI Bridge Proxy. Include the port if not using standard ports (e.g. https://aiproxy.example.com or http://internal-proxy:8888)."

  validation {
    condition     = can(regex("^https?://", var.proxy_url))
    error_message = "proxy_url must start with http:// or https://."
  }
}

variable "cert_path" {
  type        = string
  description = "Absolute path where the AI Bridge Proxy CA certificate will be saved."
  default     = "/tmp/aibridge-proxy/ca-cert.pem"

  validation {
    condition     = startswith(var.cert_path, "/")
    error_message = "cert_path must be an absolute path."
  }
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

locals {
  # Build the proxy URL with Coder authentication embedded.
  # AI Bridge Proxy expects the Coder session token as the password
  # in basic auth: http://coder:<token>@host:port
  proxy_auth_url = replace(
    var.proxy_url,
    "://",
    "://coder:${data.coder_workspace_owner.me.session_token}@"
  )
}

# These outputs are intended to be consumed by tool-specific modules,
# to set proxy environment variables scoped to their process, rather than globally.
output "proxy_auth_url" {
  description = "The AI Bridge Proxy URL with Coder authentication embedded (http://coder:<token>@host:port)."
  value       = local.proxy_auth_url
  sensitive   = true
}

output "cert_path" {
  description = "Path to the downloaded AI Bridge Proxy CA certificate."
  value       = var.cert_path
}

# Downloads the CA certificate from the Coder deployment.
# This runs on workspace start but does not block login, if the script
# fails, the workspace remains usable and the error is visible in the build logs.
# Tools that depend on the proxy will fail until the certificate is available.
resource "coder_script" "aibridge_proxy_setup" {
  agent_id           = var.agent_id
  display_name       = "AI Bridge Proxy Setup"
  icon               = "/icon/coder.svg"
  run_on_start       = true
  start_blocks_login = false
  script = templatefile("${path.module}/scripts/setup.sh", {
    CERT_PATH     = var.cert_path,
    ACCESS_URL    = data.coder_workspace.me.access_url,
    SESSION_TOKEN = data.coder_workspace_owner.me.session_token,
  })
}
