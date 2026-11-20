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

variable "command" {
  description = "Command that starts the desktop app, for example \"gimp\" or \"/opt/ghidra/ghidraRun\". The xpra session stops when this command exits."
  type        = string
  validation {
    condition     = trimspace(var.command) != ""
    error_message = "command must not be empty."
  }
}

variable "slug" {
  description = "Slug of the Coder app. Must be unique per workspace when you use the module more than once."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9](-?[a-z0-9])*$", var.slug))
    error_message = "slug must be lowercase alphanumeric with single hyphens, for example \"my-app\"."
  }
}

variable "display_name" {
  description = "Display name of the Coder app."
  type        = string
  default     = "Xpra"
}

variable "icon" {
  description = "Icon of the Coder app."
  type        = string
  default     = "/icon/desktop.svg"
}

variable "port" {
  description = "Local port of the xpra HTML5 server. Must be unique per workspace when you use the module more than once."
  type        = number
  default     = 14500
  validation {
    condition     = var.port >= 1024 && var.port <= 65535
    error_message = "port must be between 1024 and 65535."
  }
}

variable "open_in" {
  description = "Where the Coder app opens: \"slim-window\" (popup without browser UI) or \"tab\"."
  type        = string
  default     = "slim-window"
  validation {
    condition     = contains(["slim-window", "tab"], var.open_in)
    error_message = "open_in must be \"slim-window\" or \"tab\"."
  }
}

variable "share" {
  description = "Share level of the Coder app."
  type        = string
  default     = "owner"
  validation {
    condition     = contains(["owner", "authenticated", "public"], var.share)
    error_message = "share must be one of: owner, authenticated, public."
  }
}

variable "order" {
  description = "Order of the Coder app in the dashboard."
  type        = number
  default     = null
}

variable "group" {
  description = "Group of the Coder app in the dashboard."
  type        = string
  default     = null
}

variable "env" {
  description = "Environment variables for the app."
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for k in keys(var.env) : can(regex("^[A-Za-z_][A-Za-z0-9_]*$", k))])
    error_message = "env keys must be valid shell variable names."
  }
}

variable "extra_args" {
  description = "Extra arguments for \"xpra desktop\", for example [\"--min-quality=80\"]."
  type        = list(string)
  default     = []
}

variable "install_xpra" {
  description = "Install xpra from the xpra.org repository if it is not on PATH. Supports Debian and Ubuntu."
  type        = bool
  default     = true
}

variable "install_openbox" {
  description = "Install openbox from the distribution repository if it is not on PATH. Supports Debian and Ubuntu."
  type        = bool
  default     = true
}

variable "pre_install_script" {
  description = "Custom script to run before the install script."
  type        = string
  default     = null
}

variable "post_install_script" {
  description = "Custom script to run after the install script."
  type        = string
  default     = null
}

locals {
  # One directory per instance: coder-utils derives its sync names from the last two path segments.
  module_dir = "$HOME/.coder-modules/phorcys/xpra-${var.slug}"

  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL_XPRA    = tostring(var.install_xpra)
    ARG_INSTALL_OPENBOX = tostring(var.install_openbox)
  })

  start_script = templatefile("${path.module}/scripts/start.sh.tftpl", {
    ARG_MODULE_DIR = local.module_dir
    ARG_PORT       = tostring(var.port)
    ARG_COMMAND    = base64encode(var.command)
    ARG_ENV        = base64encode(join("\n", [for k, v in var.env : "${k}=${base64encode(v)}"]))
    ARG_EXTRA_ARGS = base64encode(join("\n", [for a in var.extra_args : base64encode(a)]))
  })
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.2"

  agent_id            = var.agent_id
  module_directory    = local.module_dir
  display_name_prefix = var.display_name
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  install_script      = local.install_script
  post_install_script = var.post_install_script
  start_script        = local.start_script
}

resource "coder_app" "xpra" {
  agent_id     = var.agent_id
  slug         = var.slug
  display_name = var.display_name
  icon         = var.icon
  url          = "http://localhost:${var.port}/?floating_menu=false"
  # xpra-html5 does not work behind path-based app routing.
  subdomain = true
  open_in   = var.open_in
  share     = var.share
  order     = var.order
  group     = var.group

  healthcheck {
    url       = "http://localhost:${var.port}/"
    interval  = 5
    threshold = 6
  }
}

output "scripts" {
  description = "Ordered list of coder exp sync names produced by this module, in run order."
  value       = module.coder_utils.scripts
}
