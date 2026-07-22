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
  type = list(object({
    session_name = string
    display_name = optional(string)
    slug         = optional(string)
    command      = string
  }))
  description = "List of boo sessions to create. Each entry requires session_name and command. display_name defaults to session_name; slug is derived from session_name (lowercased, '.' and '_' replaced with '-') when omitted."
  default     = []
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

variable "icon" {
  type        = string
  description = "The icon to use for boo apps and scripts."
  default     = "/icon/coder.svg"
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

variable "install_script_url" {
  type        = string
  description = "URL of the boo install.sh script. Override for air-gapped or mirrored environments."
  default     = "https://raw.githubusercontent.com/coder/boo/main/install.sh"
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
    ARG_INSTALL_BOO        = tostring(var.install_boo)
    ARG_BOO_VERSION        = var.boo_version
    ARG_INSTALL_SCRIPT_URL = var.install_script_url
  })

  sessions_resolved = [
    for s in var.sessions : {
      session_name = s.session_name
      display_name = s.display_name != null ? s.display_name : s.session_name
      slug         = s.slug != null ? s.slug : replace(lower(s.session_name), "/[._]/", "-")
      command      = s.command
    }
  ]

  sessions_map = { for s in local.sessions_resolved : s.slug => s }
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

resource "coder_app" "boo" {
  for_each = local.sessions_map

  agent_id     = var.agent_id
  slug         = each.value.slug
  display_name = each.value.display_name
  icon         = var.icon
  command      = <<-EOT
  #!/bin/bash
  export PATH="$HOME/.local/bin:$PATH"
  if boo peek '${each.value.session_name}' >/dev/null 2>&1; then
    boo attach '${each.value.session_name}'
  else
    SESSION_DIR="${local.module_dir}/${each.value.session_name}"
    mkdir -p "$SESSION_DIR/scripts"
    SCRIPT="$SESSION_DIR/scripts/start.sh"
    printf '%s' '${base64encode(each.value.command)}' | base64 -d > "$SCRIPT"
    chmod +x "$SCRIPT"
    boo new '${each.value.session_name}' -d
    boo wait '${each.value.session_name}' --idle
    boo send '${each.value.session_name}' --text "$SCRIPT" --enter
    boo attach '${each.value.session_name}'
  fi
  EOT
  order        = var.order
  group        = var.group
}

output "scripts" {
  description = "Ordered list of coder exp sync names for the install pipeline scripts, in run order."
  value       = module.coder_utils.scripts
}
