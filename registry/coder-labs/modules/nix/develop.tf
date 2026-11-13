variable "develop" {
  description = "Add a nix develop terminal app. enabled requires path and agent_id. path is raw shell syntax (quote spaces); shell selects a devShells attribute. prebuild warms and roots the environment on startup. config_override merges over config and is exported workspace-wide as NIX_CONFIG. slug, display_name, order and group customize the app."
  type = object({
    enabled         = optional(bool, false)
    path            = optional(string)
    shell           = optional(string)
    prebuild        = optional(bool, true)
    config_override = optional(any, {})
    slug            = optional(string, "nix-develop")
    display_name    = optional(string, "Nix Develop")
    order           = optional(number)
    group           = optional(string)
  })
  default = {}

  validation {
    condition     = var.develop.enabled || var.nixos.enabled
    error_message = "At least one of nixos.enabled or develop.enabled must be true."
  }
  validation {
    condition     = !var.develop.enabled || var.develop.path != null
    error_message = "develop.path is required when develop.enabled is true."
  }
  validation {
    condition     = !var.develop.enabled || (var.agent_id != null && var.agent_id != "")
    error_message = "agent_id is required when develop.enabled is true."
  }
}

locals {
  develop_module_dir = "$HOME/.coder-modules/coder-labs/nix"
  develop_script_args = {
    ARG_PATH        = var.develop.path == null ? "" : var.develop.path
    ARG_INSTALLABLE = var.develop.shell == null ? "." : ".#${var.develop.shell}"
    ARG_PROFILE_DIR = "${local.develop_module_dir}/develop"
  }
  develop_prebuild_script = templatefile("${path.module}/scripts/develop/prebuild.sh.tftpl", local.develop_script_args)
}

resource "coder_app" "develop" {
  count        = var.develop.enabled ? 1 : 0
  agent_id     = var.agent_id
  slug         = var.develop.slug
  display_name = var.develop.display_name
  icon         = var.icon
  command      = templatefile("${path.module}/scripts/develop/app.sh.tftpl", local.develop_script_args)
  order        = var.develop.order
  group        = var.develop.group
}

resource "coder_env" "nix_config" {
  count    = var.develop.enabled ? 1 : 0
  agent_id = var.agent_id
  name     = "NIX_CONFIG"
  value    = local.nix_conf.develop
}

resource "coder_env" "path" {
  count          = var.develop.enabled ? 1 : 0
  agent_id       = var.agent_id
  name           = "PATH"
  value          = "$PATH:/nix/var/nix/profiles/default/bin:$HOME/.nix-profile/bin"
  merge_strategy = "append"
}

module "coder_utils" {
  count   = var.develop.enabled && var.develop.prebuild ? 1 : 0
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.2"

  agent_id            = var.agent_id
  module_directory    = local.develop_module_dir
  display_name_prefix = "Nix Develop"
  icon                = var.icon
  install_script      = local.develop_prebuild_script
}

output "scripts" {
  description = "Ordered coder exp sync names produced by this module."
  value       = var.develop.enabled && var.develop.prebuild ? module.coder_utils[0].scripts : []
}
