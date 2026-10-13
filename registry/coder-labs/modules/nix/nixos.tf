# `nixos`: render a root-run boot script that applies a NixOS configuration
# before the Coder agent starts.

variable "nixos" {
  description = <<-EOT
    Apply a NixOS configuration on every boot.

    - `enabled`: render the boot script. Defaults to `true`.
    - `type`: how the configuration is sourced. Only `flake` is supported;
      the field exists so channel-based configurations can be added later.
    - `flake_ref`: HTTP(S) or SSH Git URL of a committed flake; optional `git+`
      prefix and `?ref=` branch. Required when `enabled`. Embedded credentials
      appear in the outputs and the checkout.
    - `flake_attr`: `nixosConfigurations` attribute to build, e.g.
      `coder-workspace-ec2-$ARCH`. `$ARCH` is replaced with `arch`. Required
      when `enabled`.
    - `arch`: `x86_64` or `aarch64`, substituted into `flake_attr`.
    - `flake_dir`: checkout to build, owned by the workspace user so the
      configuration can be edited in place.
    - `state_dir`: revision marker and rebuild lock.
    - `log_dir`: rebuild transcripts.
    - `config_override`: nix.conf settings merged over `config` (per key)
      for root's Nix: the boot rebuild, a manual `sudo nixos-rebuild`, and
      the nix-daemon that builds for every user.
  EOT
  type = object({
    enabled    = optional(bool, true)
    type       = optional(string, "flake")
    flake_ref  = optional(string)
    flake_attr = optional(string)
    arch       = optional(string, "x86_64")
    flake_dir  = optional(string, "/etc/nixos")
    state_dir  = optional(string, "/var/lib/coder-nixos")
    log_dir    = optional(string, "/var/log/coder-nixos")

    config_override = optional(any, {})
  })
  default = {}

  # Add "channel" here once channel-based configurations are implemented.
  validation {
    condition     = contains(["flake"], var.nixos.type)
    error_message = "nixos.type must be \"flake\"; channels are not supported yet."
  }

  validation {
    condition     = !var.nixos.enabled || (var.nixos.flake_ref != null && var.nixos.flake_attr != null)
    error_message = "nixos.flake_ref and nixos.flake_attr are required when nixos.enabled is true."
  }

  validation {
    condition     = var.nixos.flake_ref == null ? true : (can(regex("^(git\\+)?(https?|ssh)://", var.nixos.flake_ref)) && !can(regex("[[:cntrl:]]", var.nixos.flake_ref)) && !strcontains(var.nixos.flake_ref, "#") && (!strcontains(var.nixos.flake_ref, "?") || can(regex("\\?ref=[^&#?]+$", var.nixos.flake_ref))))
    error_message = "nixos.flake_ref must be an http(s) or ssh Git URL with optional ?ref=, without control characters, fragments, or other query parameters."
  }

  validation {
    condition     = contains(["x86_64", "aarch64"], var.nixos.arch)
    error_message = "nixos.arch must be x86_64 or aarch64."
  }

  # Same rule as var.config.
  validation {
    condition     = try(alltrue([for k, v in var.nixos.config_override : can(regex("^[a-z][a-z0-9-]*$", k)) && (can(regex("^[^[:cntrl:]]*$", v)) || (can(tolist(v)) && can([for x in tolist(v) : regex("^[^[:cntrl:]]*$", x)])))]), false)
    error_message = "nixos.config_override must be a map of nix.conf setting names (lowercase letters, digits, dashes) to strings, numbers, booleans or lists of strings, without control characters."
  }

  validation {
    condition     = alltrue([for v in [var.nixos.flake_attr, var.nixos.flake_dir, var.nixos.state_dir, var.nixos.log_dir] : v == null ? true : !can(regex("[[:cntrl:]]", v))])
    error_message = "nixos.flake_attr, flake_dir, state_dir and log_dir must not contain control characters."
  }
}

variable "values" {
  description = <<-EOT
    Extra facts for the bootstrapper to publish on the instance, passed
    straight through to `values` on whatever writes them.

    Routed through this module so the caller has one wire, and so a
    Nix-specific runtime fact has an obvious home. There are none today: the
    configuration already knows its own checkout, attribute and directories,
    because it is the thing that sets them.
  EOT
  type        = map(string)
  default     = {}
}

locals {
  nixos_flake_ref = var.nixos.flake_ref == null ? "" : var.nixos.flake_ref

  flake_url = replace(replace(local.nixos_flake_ref, "/^git\\+/", ""), "/\\?.*$/", "")

  flake_branch = try(regex("[?&]ref=([^&#]+)", local.nixos_flake_ref)[0], "")

  nixos_settings = merge(var.config, var.nixos.config_override)
  nixos_settings_text = {
    for k, v in local.nixos_settings : k => can(tolist(v)) ? join(" ", [for x in tolist(v) : tostring(x)]) : tostring(v)
  }
  nixos_nix_conf = join("\n", [for k in sort(keys(local.nixos_settings)) : "${k} = ${local.nixos_settings_text[k]}"])

  flake_attr = replace(var.nixos.flake_attr == null ? "" : var.nixos.flake_attr, "$ARCH", var.nixos.arch)
}

output "values" {
  description = "Facts to publish on the instance, for the bootstrapper's `values`."
  value       = var.values
}

output "boot_script" {
  description = "Applies the flake. Hand this to whatever runs a script on every boot; it expects to run as root. `null` when `nixos.enabled` is false."
  value = !var.nixos.enabled ? null : templatefile("${path.module}/scripts/boot.sh.tftpl", {
    lifecycle_sh = file("${path.module}/scripts/lifecycle.sh")
    flake_url    = base64encode(local.flake_url)
    flake_branch = base64encode(local.flake_branch)
    flake_attr   = base64encode(local.flake_attr)
    flake_dir    = base64encode(var.nixos.flake_dir)
    state_dir    = base64encode(var.nixos.state_dir)
    log_dir      = base64encode(var.nixos.log_dir)
    nix_conf     = base64encode(local.nixos_nix_conf)
  })
}

output "nixos_nix_conf" {
  description = "nix.conf text applied to root's Nix on the instance (`config` merged with `nixos.config_override`). `null` when `nixos.enabled` is false."
  value       = !var.nixos.enabled ? null : local.nixos_nix_conf
}

output "flake_uri" {
  description = "The reference actually built, normalised for display. `null` when `nixos.enabled` is false."
  value       = !var.nixos.enabled ? null : "${local.flake_url}${local.flake_branch == "" ? "" : "?ref=${local.flake_branch}"}#${local.flake_attr}"
}

output "flake_attr" {
  description = "`nixosConfigurations` attribute after `$ARCH` substitution. `null` when `nixos.enabled` is false."
  value       = !var.nixos.enabled ? null : local.flake_attr
}

output "flake_dir" {
  description = "Checkout on the instance. `null` when `nixos.enabled` is false."
  value       = !var.nixos.enabled ? null : var.nixos.flake_dir
}

output "log_dir" {
  description = "Where rebuild transcripts are written. `null` when `nixos.enabled` is false."
  value       = !var.nixos.enabled ? null : var.nixos.log_dir
}

output "version_command" {
  description = <<-EOT
    Shell that reports the running NixOS version, and whether a generation is
    staged but not yet booted. For a `coder_agent` metadata block, which has
    to be declared inline on the agent. `null` when `nixos.enabled` is false.
  EOT
  value       = !var.nixos.enabled ? null : <<-EOT
    version=$(nixos-version 2>/dev/null || echo unknown)
    if [ "$(readlink -f /run/current-system)" = "$(readlink -f /nix/var/nix/profiles/system)" ]; then
      echo "$version"
    else
      echo "$version (restart to apply update)"
    fi
  EOT
}
