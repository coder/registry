# `develop`: a "Nix Develop" terminal app that enters a project's
# `nix develop` shell, with its dependencies prebuilt on workspace start.

variable "develop" {
  description = <<-EOT
    Enter a `nix develop` shell from a project flake.

    - `enabled`: add the Nix Develop app (and prebuild). Defaults to `false`.
      Requires `path` and `agent_id`.
    - `path`: directory containing the project's `flake.nix`. Absolute, or
      relative to the workspace user's home directory (`~/` is accepted).
    - `shell`: `devShells` attribute to enter; defaults to the flake's default
      shell.
    - `prebuild`: on workspace start, fetch/build everything the dev shell
      needs and keep it as a GC root, so opening the app is instant.
      Defaults to `true`.
    - `config_override`: nix.conf settings merged over `config` (per key) for
      the workspace user's `nix` client.
    - `export_config`: also export those settings workspace-wide as
      `NIX_CONFIG`, so a `nix develop` run by hand gets them. Defaults to
      `true`.
    - `display_name`, `order`, `group`: presentation of the app.
  EOT
  type = object({
    enabled         = optional(bool, false)
    path            = optional(string)
    shell           = optional(string)
    prebuild        = optional(bool, true)
    config_override = optional(any, {})
    export_config   = optional(bool, true)
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

  validation {
    condition     = alltrue([for v in [var.develop.path, var.develop.shell] : v == null ? true : (v != "" && !can(regex("[[:cntrl:]]", v)))])
    error_message = "develop.path and develop.shell must be non-empty and must not contain control characters."
  }

  # Same rule as var.config.
  validation {
    condition     = try(alltrue([for k, v in var.develop.config_override : can(regex("^[a-z][a-z0-9-]*$", k)) && (can(regex("^[^[:cntrl:]]*$", v)) || (can(tolist(v)) && can([for x in tolist(v) : regex("^[^[:cntrl:]]*$", x)])))]), false)
    error_message = "develop.config_override must be a map of nix.conf setting names (lowercase letters, digits, dashes) to strings, numbers, booleans or lists of strings, without control characters."
  }
}

locals {
  develop_module_dir = "$HOME/.coder-modules/coder-labs/nix"
  develop_profile    = "${local.develop_module_dir}/develop/profile"

  # When `nixos` is enabled, the daemon already has the daemon-only settings
  # (see nixos.tf); don't resend them from an untrusted client.
  develop_settings = {
    for k, v in merge(var.config, var.develop.config_override) : k => v
    if !(var.nixos.enabled && contains(local.daemon_only_settings, k))
  }
  develop_settings_text = {
    for k, v in local.develop_settings : k => can(tolist(v)) ? join(" ", [for x in tolist(v) : tostring(x)]) : tostring(v)
  }
  develop_nix_conf = join("\n", [for k in sort(keys(local.develop_settings)) : "${k} = ${local.develop_settings_text[k]}"])

  # Settings reach the module's own `nix` processes through `coder_env` when
  # exported; otherwise they are appended to NIX_CONFIG inline.
  develop_inline_conf = var.develop.export_config ? "" : local.develop_nix_conf

  # Values are POSIX single-quoted ('\'' escapes a quote).
  develop_installable = var.develop.shell == null ? "." : ".#${var.develop.shell}"
  develop_nix_args    = "--extra-experimental-features 'nix-command flakes' develop --profile \"${local.develop_profile}\" '${replace(local.develop_installable, "'", "'\\''")}'"

  # `~/x` and `x` resolve from $HOME; absolute paths are used as-is.
  develop_path_relative = var.develop.path == null ? "" : trimprefix(trimprefix(var.develop.path, "~/"), "./")
  develop_path_shell = (
    var.develop.path == null ? "" :
    startswith(var.develop.path, "/") ? "'${replace(var.develop.path, "'", "'\\''")}'" :
    var.develop.path == "~" ? "\"$HOME\"" :
    "\"$HOME\"/'${replace(local.develop_path_relative, "'", "'\\''")}'"
  )

  develop_env_prefix = local.develop_inline_conf == "" ? "" : "NIX_CONFIG=\"$(printf '%s\\n' \"$${NIX_CONFIG:-}\"; printf %s '${base64encode(local.develop_inline_conf)}' | base64 -d)\" "

  develop_command = "mkdir -p \"${local.develop_module_dir}/develop\" && cd ${local.develop_path_shell} && ${local.develop_env_prefix}exec nix ${local.develop_nix_args}"

  develop_prebuild_script = templatefile("${path.module}/scripts/develop-prebuild.sh.tftpl", {
    ARG_PATH        = base64encode(var.develop.path == null ? "" : var.develop.path)
    ARG_INSTALLABLE = base64encode(local.develop_installable)
    ARG_NIX_CONF    = base64encode(local.develop_inline_conf)
    ARG_PROFILE_DIR = "${local.develop_module_dir}/develop"
  })
}

resource "coder_app" "develop" {
  count        = var.develop.enabled ? 1 : 0
  agent_id     = var.agent_id
  slug         = "nix-develop"
  display_name = var.develop.display_name
  icon         = var.icon
  command      = local.develop_command
  order        = var.develop.order
  group        = var.develop.group
}

resource "coder_env" "nix_config" {
  count    = var.develop.enabled && var.develop.export_config && local.develop_nix_conf != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "NIX_CONFIG"
  value    = local.develop_nix_conf
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

output "develop_command" {
  description = "Shell command the Nix Develop app runs: enters `develop.path` and execs `nix develop`. `null` when `develop.enabled` is false."
  value       = var.develop.enabled ? local.develop_command : null
}

output "develop_nix_conf" {
  description = "nix.conf text for the workspace user's `nix` client (`config` merged with `develop.config_override`, minus daemon-only settings when `nixos` is enabled). `null` when `develop.enabled` is false."
  value       = var.develop.enabled ? local.develop_nix_conf : null
}

output "scripts" {
  description = "Ordered list of coder exp sync names produced by this module, in run order."
  value       = var.develop.enabled && var.develop.prebuild ? module.coder_utils[0].scripts : []
}
