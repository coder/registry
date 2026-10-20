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
  description = "The icon to use for the Kiro Crew apps and scripts."
  type        = string
  default     = "/icon/kiro.svg"
}

variable "port" {
  description = "Port the Kiro Crew gateway listens on inside the workspace."
  type        = number
  default     = 8899

  validation {
    condition     = var.port >= 1 && var.port <= 65535
    error_message = "port must be between 1 and 65535."
  }
}

variable "redirect_port" {
  description = "Loopback port for the token-minting redirector that fronts the dashboard so the Kiro Crew app tile opens an authenticated dashboard."
  type        = number
  default     = 8898

  validation {
    condition     = var.redirect_port >= 1 && var.redirect_port <= 65535
    error_message = "redirect_port must be between 1 and 65535."
  }
}

variable "slug" {
  description = "Slug for the visible Kiro Crew app. The hidden dashboard app uses \"<slug>-dashboard\"."
  type        = string
  default     = "kirocrew"

  validation {
    condition     = can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.slug))
    error_message = "slug must contain only lowercase letters, numbers, and single hyphens between them."
  }
}

variable "order" {
  description = "The order determines the position of the app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  type        = number
  default     = null
}

variable "group" {
  description = "The name of a group that this app belongs to."
  type        = string
  default     = null
}

variable "share" {
  description = "The sharing level for the Kiro Crew apps: 'owner', 'authenticated', or 'public'."
  type        = string
  default     = "owner"

  validation {
    condition     = contains(["owner", "authenticated", "public"], var.share)
    error_message = "share must be 'owner', 'authenticated', or 'public'."
  }
}

variable "open_in" {
  description = "Where the Kiro Crew app opens: 'tab' or 'slim-window'."
  type        = string
  default     = "slim-window"

  validation {
    condition     = contains(["tab", "slim-window"], var.open_in)
    error_message = "open_in must be 'tab' or 'slim-window'."
  }
}

variable "use_cached" {
  description = "Skip running the Kiro CLI and Kiro Crew installers when the binaries are already present."
  type        = bool
  default     = true
}

variable "extra_mcp_json" {
  description = "Optional MCP configuration JSON to deep-merge into ~/.kiro/settings/mcp.json. Keys from this value replace existing keys with the same name; other existing keys are kept."
  type        = string
  default     = ""

  validation {
    condition     = var.extra_mcp_json == "" || can(jsondecode(var.extra_mcp_json))
    error_message = "extra_mcp_json must be empty or valid JSON."
  }
}

variable "aws_builder_id_token" {
  description = "Optional AWS Builder ID access token, for example from a coder_external_auth data source. Exported to the workspace as KIRO_AWS_BUILDER_ID_TOKEN."
  type        = string
  default     = ""
  sensitive   = true
}

variable "allowed_origins" {
  description = "Comma-separated extra origins that the Kiro Crew gateway trusts in its Host/Origin allowlist, for example the Coder access URL origin. The dashboard app origin is always included. Passed to the gateway as KIROCREW_CORS_ORIGINS."
  type        = string
  default     = ""
}

variable "dashboard_origin" {
  description = "Override for the external origin of the hidden dashboard app, for example when the deployment's wildcard access URL differs from its access URL. When empty, the module derives \"<scheme>://<slug>-dashboard--<workspace>--<owner>.<access-host>\" from the access URL."
  type        = string
  default     = ""

  validation {
    condition     = var.dashboard_origin == "" || can(regex("^https?://[^/]+$", var.dashboard_origin))
    error_message = "dashboard_origin must be empty or an origin such as 'https://app.example.com' with no path."
  }
}

variable "pre_install_script" {
  description = "Custom script to run before installing Kiro CLI and Kiro Crew, for example to install system packages."
  type        = string
  default     = null
}

variable "post_install_script" {
  description = "Custom script to run after installing Kiro CLI and Kiro Crew, before the gateway starts."
  type        = string
  default     = null
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

locals {
  module_dir_name  = ".coder-modules/coder-labs/kiro-crew"
  module_directory = "$HOME/${local.module_dir_name}"

  dashboard_slug = "${var.slug}-dashboard"
  access_scheme  = startswith(data.coder_workspace.me.access_url, "http://") ? "http" : "https"
  access_host    = trimsuffix(replace(replace(data.coder_workspace.me.access_url, "https://", ""), "http://", ""), "/")

  # Coder serves subdomain apps at <slug>--<workspace>--<owner>.<wildcard-host>.
  # The redirector sends the browser here with a freshly minted token, and the
  # gateway must trust this origin or it rejects proxied requests with
  # "Host header not allowed.".
  dashboard_origin = (
    var.dashboard_origin != ""
    ? var.dashboard_origin
    : "${local.access_scheme}://${local.dashboard_slug}--${data.coder_workspace.me.name}--${data.coder_workspace_owner.me.name}.${local.access_host}"
  )

  gateway_allowed_origins = (
    trimspace(var.allowed_origins) != ""
    ? "${local.dashboard_origin},${trimspace(var.allowed_origins)}"
    : local.dashboard_origin
  )

  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_USE_CACHED     = tostring(var.use_cached)
    ARG_EXTRA_MCP_JSON = var.extra_mcp_json != "" ? base64encode(var.extra_mcp_json) : ""
  })

  start_script = templatefile("${path.module}/scripts/start.sh.tftpl", {
    ARG_MODULE_DIRECTORY = local.module_directory
    ARG_PORT             = tostring(var.port)
    ARG_REDIRECT_PORT    = tostring(var.redirect_port)
    ARG_ALLOWED_ORIGINS  = base64encode(local.gateway_allowed_origins)
    ARG_DASHBOARD_URL    = base64encode(local.dashboard_origin)
  })
}

# The token is exported through the agent environment so it is never rendered
# into a script.
resource "coder_env" "aws_builder_id_token" {
  count    = var.aws_builder_id_token != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "KIRO_AWS_BUILDER_ID_TOKEN"
  value    = var.aws_builder_id_token
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.2"

  agent_id            = var.agent_id
  module_directory    = local.module_directory
  display_name_prefix = "Kiro Crew"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  install_script      = local.install_script
  post_install_script = var.post_install_script
  start_script        = local.start_script
}

# The visible tile points at a loopback redirector that mints a short-lived
# gateway token and redirects to the hidden dashboard app with ?token=. Kiro
# Crew requires a token for every browser request, and a static coder_app URL
# cannot embed a token that only exists at runtime.
resource "coder_app" "kiro_crew" {
  agent_id     = var.agent_id
  slug         = var.slug
  display_name = "Kiro Crew"
  url          = "http://localhost:${var.redirect_port}/"
  icon         = var.icon
  subdomain    = true
  share        = var.share
  order        = var.order
  group        = var.group
  open_in      = var.open_in

  healthcheck {
    url       = "http://localhost:${var.redirect_port}/healthz"
    interval  = 5
    threshold = 6
  }
}

# Serves the dashboard SPA and its websocket through Coder's subdomain proxy.
resource "coder_app" "kiro_crew_dashboard" {
  agent_id  = var.agent_id
  slug      = local.dashboard_slug
  url       = "http://localhost:${var.port}/"
  subdomain = true
  share     = var.share
  hidden    = true
  open_in   = var.open_in

  healthcheck {
    url       = "http://localhost:${var.port}/health"
    interval  = 5
    threshold = 6
  }
}

output "kirocrew_url" {
  description = "Local URL of the Kiro Crew gateway inside the workspace."
  value       = "http://localhost:${var.port}/"
}

output "dashboard_origin" {
  description = "External origin of the hidden Kiro Crew dashboard app that the redirector sends the browser to."
  value       = local.dashboard_origin
}

output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module creates, in run order (pre_install, install, post_install, start). Scripts that were not configured are absent from the list."
  value       = module.coder_utils.scripts
}
