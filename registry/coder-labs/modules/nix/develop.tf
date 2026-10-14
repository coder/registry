# `develop`: a "Nix Develop" terminal app that enters a project's
# `nix develop` shell, with its dependencies prebuilt on workspace start.

variable "develop" {
  description = <<-EOT
    Enter a `nix develop` shell from a project flake.

    - `enabled`: add the Nix Develop app (and prebuild). Defaults to `false`.
      Requires `path` and `agent_id`.
    - `path`: directory containing the project's `flake.nix`. Inserted into
      the scripts as written (shell syntax), so `~/project` and
      `$HOME/project` work; quote it yourself if it contains spaces.
    - `shell`: `devShells` attribute to enter; defaults to the flake's default
      shell.
    - `prebuild`: on workspace start, fetch/build everything the dev shell
      needs and keep it as a GC root, so opening the app is instant.
      Defaults to `true`.
    - `config_override`: nix.conf settings merged over `config` (per key) for
      the workspace user's `nix` client. They are exported workspace-wide as
      `NIX_CONFIG`, so the user's own `nix` commands behave like the module's.
    - `slug`, `display_name`, `order`, `group`: presentation of the app.
  EOT
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

  validation {
    condition     = var.develop.shell == null ? true : (var.develop.shell != "" && !can(regex("[[:cntrl:]]", var.develop.shell)))
    error_message = "develop.shell must be non-empty and must not contain control characters."
  }

  # Same rule as var.config.
  validation {
    condition     = try(length(keys(var.develop.config_override)) >= 0 && alltrue([for k, v in var.develop.config_override : can(regex("^[a-z][a-z0-9-]*$", k)) && (can(regex("^[^[:cntrl:]]*$", v)) || (can(tolist(v)) && can([for x in tolist(v) : regex("^[^[:cntrl:]]*$", x)])))]), false)
    error_message = "develop.config_override must be a map of nix.conf setting names (lowercase letters, digits, dashes) to strings, numbers, booleans or lists of strings, without control characters."
  }
}

locals {
  develop_module_dir = "$HOME/.coder-modules/coder-labs/nix"

  # When `nixos` is enabled, the daemon already has the daemon-only settings
  # (see nixos.tf); don't resend them from an untrusted client.
  develop_settings_merged = {
    for k, v in merge(var.config, var.develop.config_override) : k => v
    if !(var.nixos.enabled && contains(local.daemon_only_settings, k))
  }
  develop_settings = merge(local.develop_settings_merged, {
    extra-experimental-features = distinct(concat(
      try(tolist(local.develop_settings_merged["extra-experimental-features"]), compact(split(" ", tostring(lookup(local.develop_settings_merged, "extra-experimental-features", ""))))),
      local.required_experimental_features,
    ))
  })
  develop_settings_text = {
    for k, v in local.develop_settings : k => can(tolist(v)) ? join(" ", [for x in tolist(v) : tostring(x)]) : tostring(v)
  }
  develop_nix_conf = join("\n", [for k in sort(keys(local.develop_settings)) : "${k} = ${local.develop_settings_text[k]}"])

  develop_installable = var.develop.shell == null ? "." : ".#${var.develop.shell}"

  develop_script_args = {
    ARG_PATH        = var.develop.path == null ? "" : var.develop.path
    ARG_INSTALLABLE = base64encode(local.develop_installable)
    ARG_PROFILE_DIR = "${local.develop_module_dir}/develop"
    NIX_ENV_SH      = file("${path.module}/scripts/develop/nix-env.sh")
  }

  develop_command         = templatefile("${path.module}/scripts/develop/app.sh.tftpl", local.develop_script_args)
  develop_prebuild_script = templatefile("${path.module}/scripts/develop/prebuild.sh.tftpl", local.develop_script_args)
}

resource "coder_app" "develop" {
  count        = var.develop.enabled ? 1 : 0
  agent_id     = var.agent_id
  slug         = var.develop.slug
  display_name = var.develop.display_name
  icon         = var.icon
  command      = local.develop_command
  order        = var.develop.order
  group        = var.develop.group
}

resource "coder_env" "nix_config" {
  count    = var.develop.enabled ? 1 : 0
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
  description = "Bash script the Nix Develop app runs: enters `develop.path` and execs `nix develop`. `null` when `develop.enabled` is false."
  value       = var.develop.enabled ? local.develop_command : null
}

output "develop_nix_conf" {
  description = "nix.conf text for the workspace user's `nix` client: `config` merged with `develop.config_override` (minus daemon-only settings when `nixos` is enabled), plus the `nix-command` and `flakes` experimental features. `null` when `develop.enabled` is false."
  value       = var.develop.enabled ? local.develop_nix_conf : null
}

output "scripts" {
  description = "Ordered list of coder exp sync names produced by this module, in run order."
  value       = var.develop.enabled && var.develop.prebuild ? module.coder_utils[0].scripts : []
}
