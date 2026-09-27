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
  description = "The ID of a Coder agent."
  type        = string
}

variable "port" {
  description = "The port Selkies listens on, on the workspace's loopback addresses."
  type        = number
  default     = 8080

  validation {
    condition     = var.port >= 1 && var.port <= 65535 && floor(var.port) == var.port
    error_message = "port must be an integer between 1 and 65535."
  }
}

variable "desktop_environment" {
  description = "The desktop to start: a session installed in the workspace, by name (xfce, kde, lxqt, gnome, mate), or a command. Empty starts the workspace's default desktop."
  type        = string
  default     = ""
}

variable "wayland" {
  description = "Stream through Selkies' Wayland backend instead of an Xvfb."
  type        = bool
  default     = false
}

variable "install_selkies" {
  description = "Install what the workspace lacks of Selkies and Xvfb, as root or with passwordless sudo. Set to false when the image carries both."
  type        = bool
  default     = true
}

variable "selkies_version" {
  description = "The Selkies release to install, such as 2.0.0. Empty installs the latest."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^([0-9A-Za-z][0-9A-Za-z._-]*)?$", var.selkies_version))
    error_message = "selkies_version must be a release tag such as 2.0.0, or empty for the latest."
  }
}

variable "release_url" {
  description = "Where Selkies' releases are downloaded from: GitHub's, or a mirror laid out the same way (<release_url>/download/<version>/<file>). A mirror without a /latest redirect needs selkies_version."
  type        = string
  default     = "https://github.com/selkies-project/selkies/releases"

  validation {
    condition     = can(regex("^https?://[^\\s'\"]+[^/\\s'\"]$", var.release_url))
    error_message = "release_url must be an http(s) URL without quotes or a trailing slash."
  }
}

variable "order" {
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  type        = number
  default     = null
}

variable "group" {
  description = "The name of a group that this app belongs to."
  type        = string
  default     = null
}

variable "subdomain" {
  description = "Is subdomain sharing enabled in your cluster?"
  type        = bool
  default     = true
}

variable "share" {
  description = "Who can open the app: the workspace's owner, any authenticated user, or anyone."
  type        = string
  default     = "owner"

  validation {
    condition     = var.share == "owner" || var.share == "authenticated" || var.share == "public"
    error_message = "Incorrect value. Please set either 'owner', 'authenticated', or 'public'."
  }
}

locals {
  icon             = "/icon/selkies.svg"
  module_directory = "$HOME/.coder-modules/selkies-project/selkies"

  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL     = tostring(var.install_selkies)
    ARG_WAYLAND     = tostring(var.wayland)
    ARG_VERSION     = var.selkies_version
    ARG_RELEASE_URL = var.release_url
  })

  start_script = templatefile("${path.module}/scripts/start.sh.tftpl", {
    ARG_PORT        = tostring(var.port)
    ARG_WAYLAND     = tostring(var.wayland)
    ARG_DESKTOP_B64 = base64encode(var.desktop_environment)
  })
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.2"

  agent_id            = var.agent_id
  module_directory    = local.module_directory
  display_name_prefix = "Selkies"
  icon                = local.icon
  install_script      = local.install_script
  start_script        = local.start_script
}

# Selkies derives its path prefix from the URL it is loaded from, so a path app works as well as a subdomain.
resource "coder_app" "selkies" {
  agent_id     = var.agent_id
  slug         = "selkies"
  display_name = "Selkies"
  url          = "http://localhost:${var.port}"
  icon         = local.icon
  subdomain    = var.subdomain
  share        = var.share
  order        = var.order
  group        = var.group

  healthcheck {
    url       = "http://localhost:${var.port}/api/health"
    interval  = 5
    threshold = 6
  }
}

output "scripts" {
  description = "Ordered list of coder exp sync names for the scripts this module runs: the install script, then the start script."
  value       = module.coder_utils.scripts
}
