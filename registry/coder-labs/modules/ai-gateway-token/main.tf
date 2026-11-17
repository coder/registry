terraform {
  required_version = ">= 1.9"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.12"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.4"
    }
  }
}

variable "scopes" {
  description = "API key scopes for the token. The default lets the token read only the owner's own profile, which is enough to authenticate with AI Gateway."
  type        = list(string)
  default     = ["user:read_personal"]

  validation {
    condition     = length(var.scopes) > 0 && !contains(var.scopes, "coder:all") && !contains(var.scopes, "all")
    error_message = "scopes must be non-empty and must not grant full access."
  }
}

variable "lifetime_hours" {
  description = "How long the token is valid, in hours. 0 uses the deployment's default token lifetime. The token is not revoked when the workspace stops, so it stays valid until it expires."
  type        = number
  default     = 0

  validation {
    condition     = var.lifetime_hours >= 0 && floor(var.lifetime_hours) == var.lifetime_hours
    error_message = "lifetime_hours must be a whole number greater than or equal to 0."
  }
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

# The owner's session token has full access to the Coder API. It is used here
# only by the provisioner, during the build, to create a token with narrow
# scopes. Only that narrow token is returned to the template.
#
# timestamp() defers the request to apply, so a plan creates nothing. A
# prebuild gets no token; the claim build creates one for the new owner.
locals {
  mint = (
    data.coder_workspace.me.start_count > 0 &&
    !data.coder_workspace.me.is_prebuild &&
    data.coder_workspace_owner.me.session_token != ""
  )
}

data "http" "token" {
  count  = local.mint ? 1 : 0
  url    = "${data.coder_workspace.me.access_url}/api/v2/users/me/keys/tokens"
  method = "POST"
  request_headers = {
    "Coder-Session-Token" = data.coder_workspace_owner.me.session_token
    "Content-Type"        = "application/json"
  }
  request_body = jsonencode(merge(
    {
      token_name = "ai-gateway-${substr(data.coder_workspace.me.id, 0, 8)}-${formatdate("YYYYMMDDhhmmss", timestamp())}"
      scopes     = var.scopes
    },
    # The API takes the lifetime in nanoseconds.
    var.lifetime_hours > 0 ? { lifetime = var.lifetime_hours * 3600 * 1000000000 } : {},
  ))

  lifecycle {
    postcondition {
      condition     = self.status_code == 201
      error_message = "Could not create the AI Gateway token: HTTP ${self.status_code}."
    }
  }
}

output "token" {
  description = "A Coder API token with only the requested scopes. Empty for prebuilds and stopped workspaces."
  value       = local.mint ? jsondecode(data.http.token[0].response_body).key : ""
  sensitive   = true
}
