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
    condition     = can(regex("^(git\\+)?(https?|ssh)://", var.flake_ref)) && !can(regex("^(git\\+)?https?://[^/?#]*@", var.flake_ref)) && !can(regex("[[:cntrl:]]", var.flake_ref))
    error_message = "flake_ref must be an http(s) or ssh Git URL without HTTP credentials or control characters. Use root-managed Git authentication instead of URL userinfo."
  }
}

variable "flake_attr" {
  description = "`nixosConfigurations` attribute to build. `$ARCH` is replaced with `arch`."
  type        = string
  default     = "coder-workspace-ec2-$ARCH"

  validation {
    condition     = !can(regex("[[:cntrl:]]", var.flake_attr))
    error_message = "flake_attr must not contain control characters."
  }
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

  validation {
    condition     = !can(regex("[[:cntrl:]]", var.flake_dir))
    error_message = "flake_dir must not contain control characters."
  }
}

variable "state_dir" {
  description = "Revision marker and rebuild lock."
  type        = string
  default     = "/var/lib/coder-nixos"

  validation {
    condition     = !can(regex("[[:cntrl:]]", var.state_dir))
    error_message = "state_dir must not contain control characters."
  }
}

variable "log_dir" {
  description = "Rebuild transcripts."
  type        = string
  default     = "/var/log/coder-nixos"

  validation {
    condition     = !can(regex("[[:cntrl:]]", var.log_dir))
    error_message = "log_dir must not contain control characters."
  }
}

locals {
  flake_url = replace(replace(var.flake_ref, "/^git\\+/", ""), "/\\?.*$/", "")

  flake_branch = try(regex("[?&]ref=([^&#]+)", var.flake_ref)[0], "")

  flake_attr = replace(var.flake_attr, "$ARCH", var.arch)

  lifecycle_sh = file("${path.module}/scripts/lifecycle.sh")
}

output "values" {
  description = "Facts to publish on the instance, for the bootstrapper's `values`."
  value       = var.values
}

output "boot_script" {
  description = "Applies the flake. Hand this to whatever runs a script on every boot; it expects to run as root."
  value = templatefile("${path.module}/scripts/boot.sh.tftpl", {
    lifecycle_sh = local.lifecycle_sh
    flake_url    = base64encode(local.flake_url)
    flake_branch = base64encode(local.flake_branch)
    flake_attr   = base64encode(local.flake_attr)
    flake_dir    = base64encode(var.flake_dir)
    state_dir    = base64encode(var.state_dir)
    log_dir      = base64encode(var.log_dir)
  })
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
  value       = <<-EOT
    version=$(nixos-version 2>/dev/null || echo unknown)
    if [ "$(readlink -f /run/current-system)" = "$(readlink -f /nix/var/nix/profiles/system)" ]; then
      echo "$version"
    else
      echo "$version (restart to apply update)"
    fi
  EOT
}
