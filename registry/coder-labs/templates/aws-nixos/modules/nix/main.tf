# The flake lifecycle at boot: clone or fast-forward the checkout, decide
# whether the running system is out of date, and rebuild it.
#
# Nothing here knows about EC2, user-data or how the instance was started --
# the boot path is exposed as a string for whatever puts scripts on the
# machine, which on AWS is ../amazon-init.
#
# Keeping the machine current *afterwards* is not this module's job either.
# That is `system.autoUpgrade` in the configuration itself, on a systemd timer
# the machine's owner can read and change.

terraform {
  required_version = ">= 1.3"
}

variable "flake_ref" {
  description = <<-EOT
    Git reference to the flake, in the form `nix` itself accepts:
    `https://host/org/repo`, optionally with a `git+` prefix and a `?ref=`
    branch. Without `?ref=` the remote's default branch is used.

    The configuration must be committed -- a Git flake reference only ever
    sees committed files.
  EOT
  type        = string

  validation {
    condition     = can(regex("^(git\\+)?(https?|ssh)://", var.flake_ref))
    error_message = "flake_ref must be an http(s) or ssh Git URL, optionally prefixed with git+."
  }
}

variable "flake_attr" {
  description = "`nixosConfigurations` attribute to build. `$ARCH` is replaced with `arch`."
  type        = string
  default     = "coder-workspace-$ARCH"
}

variable "arch" {
  description = "Nix architecture name substituted into `flake_attr`."
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "aarch64"], var.arch)
    error_message = "arch must be x86_64 or aarch64."
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

variable "flake_dir" {
  description = "Checkout to build. Owned by the workspace user so the configuration can be edited in place."
  type        = string
  default     = "/etc/nixos"
}

variable "state_dir" {
  description = "Revision marker and rebuild lock."
  type        = string
  default     = "/var/lib/coder-nixos"
}

variable "log_dir" {
  description = "Rebuild transcripts."
  type        = string
  default     = "/var/log/coder-nixos"
}

locals {
  # `git clone` is what runs on the instance, so reduce the reference to a
  # plain remote: strip a `git+` scheme prefix and any query string.
  flake_url = replace(replace(var.flake_ref, "/^git\\+/", ""), "/\\?.*$/", "")

  # An absent `?ref=` means the remote's default branch, resolved on the
  # instance -- Terraform cannot know it without talking to the remote.
  flake_branch = try(regex("[?&]ref=([^&#]+)", var.flake_ref)[0], "")

  flake_attr = replace(var.flake_attr, "$ARCH", var.arch)

  lifecycle_sh = file("${path.module}/scripts/lifecycle.sh")

  script_args = {
    LIFECYCLE_SH     = local.lifecycle_sh
    ARG_FLAKE_URL    = local.flake_url
    ARG_FLAKE_BRANCH = local.flake_branch
    ARG_FLAKE_ATTR   = local.flake_attr
    ARG_FLAKE_DIR    = var.flake_dir
    ARG_STATE_DIR    = var.state_dir
    ARG_LOG_DIR      = var.log_dir
  }
}

output "values" {
  description = "Facts to publish on the instance, for the bootstrapper's `values`."
  value       = var.values
}

output "boot_script" {
  description = "Applies the flake. Hand this to whatever runs a script on every boot; it expects to run as root."
  value       = templatefile("${path.module}/scripts/boot.sh.tftpl", local.script_args)
}

output "flake_uri" {
  description = "The reference actually built, normalised for display."
  value       = "${local.flake_url}${local.flake_branch == "" ? "" : "?ref=${local.flake_branch}"}#${local.flake_attr}"
}

output "flake_attr" {
  description = "`nixosConfigurations` attribute after `$ARCH` substitution."
  value       = local.flake_attr
}

output "flake_dir" {
  description = "Checkout on the instance."
  value       = var.flake_dir
}

output "log_dir" {
  description = "Where rebuild transcripts are written."
  value       = var.log_dir
}

output "version_command" {
  description = <<-EOT
    Shell that reports the running NixOS version, and whether a generation is
    staged but not yet booted. For a `coder_agent` metadata block, which has
    to be declared inline on the agent.
  EOT
  # /run/current-system is the activated system; /run/booted-system is what
  # the kernel booted and still points at the previous generation after a
  # switch, which would mark every new workspace as needing a restart.
  value = <<-EOT
    version=$(nixos-version 2>/dev/null || echo unknown)
    if [ "$(readlink -f /run/current-system)" = "$(readlink -f /nix/var/nix/profiles/system)" ]; then
      echo "$version"
    else
      echo "$version (restart to apply update)"
    fi
  EOT
}
