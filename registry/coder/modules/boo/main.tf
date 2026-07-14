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
  type        = string
  description = "The ID of a Coder agent."
}

variable "sessions" {
  type        = map(string)
  description = "Map of session names to commands. A boo session and coder_app are created for each entry."
}

variable "folder" {
  type        = string
  description = "The working directory for boo sessions."
  default     = "/home/coder"
}

variable "install_boo" {
  type        = bool
  description = "Whether to install boo."
  default     = true
}

variable "boo_version" {
  type        = string
  description = "The version of boo to install. Use 'latest' to accept any installed version or always install the latest release."
  default     = "latest"
}

variable "display_name" {
  type        = string
  description = "The display name prefix for boo apps. Each app is shown as '<display_name>: <session_name>'."
  default     = "Boo"
}

variable "slug" {
  type        = string
  description = "The slug prefix for boo apps. Each app slug is '<slug>-<session_name>'."
  default     = "boo"
}

variable "icon" {
  type        = string
  description = "The icon to use for boo apps and scripts."
  default     = "/icon/boo.svg"
}

variable "order" {
  type        = number
  description = "The order determines the position of apps in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  default     = null
}

variable "group" {
  type        = string
  description = "The name of a group that boo apps belong to."
  default     = null
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing boo."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing boo."
  default     = null
}

locals {
  module_dir = "$HOME/.coder-modules/coder/boo"

  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL_BOO = tostring(var.install_boo)
    ARG_BOO_VERSION = var.boo_version
  })

  # Last sync name from the install pipeline; per-session start scripts wait on this.
  install_phase_last = module.coder_utils.scripts[length(module.coder_utils.scripts) - 1]
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = local.module_dir
  display_name_prefix = "Boo"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  post_install_script = var.post_install_script
  install_script      = local.install_script
}

# resource "coder_script" "boo_start" {
#   for_each = var.sessions

#   agent_id     = var.agent_id
#   display_name = "${var.display_name}: Start ${each.key}"
#   icon         = var.icon
#   run_on_start = true
#   script = templatefile("${path.module}/scripts/start.sh.tftpl", {
#     ARG_SESSION_NAME = each.key
#     ARG_FOLDER       = var.folder
#     ARG_COMMAND      = base64encode(each.value)
#     ARG_LOG_PATH     = "${local.module_dir}/logs/${each.key}/start.log"
#     ARG_SYNC_NAME    = "coder-boo-${each.key}-start_script"
#     ARG_INSTALL_SYNC = local.install_phase_last
#   })
# }

resource "coder_app" "boo" {
  for_each = var.sessions

  agent_id     = var.agent_id
  slug         = "${var.slug}-${replace(each.key, "_", "-")}"
  display_name = "${var.display_name}: ${each.key}"
  icon         = var.icon
  command      = <<-EOT
  #!/bin/bash
  export PATH="$HOME/.local/bin:$PATH"
  if boo peek '${each.key}' >/dev/null 2>&1; then
    boo attach '${each.key}'
  else
    boo new '${each.key}'
    '${each.value}'
  fi
  EOT
  order        = var.order
  group        = var.group
}

output "scripts" {
  description = "Ordered list of coder exp sync names for the coder_script resources this module creates, in run order. Includes install phase scripts followed by per-session start scripts (sorted by session name)."
  value = concat(
    module.coder_utils.scripts,
    [for name in sort(keys(var.sessions)) : "coder-boo-${name}-start_script"]
  )
}
