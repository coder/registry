variable "nixos" {
  description = "Apply flake_ref (Git URL, optional git+ prefix and ?ref= branch) and flake_attr (nixosConfigurations attribute) on boot. enabled defaults to true; both flake fields are required when enabled. flake_dir holds the checkout, log_dir holds rebuild transcripts, and config_override supplies nix.conf settings for the boot rebuild."
  type = object({
    enabled         = optional(bool, true)
    flake_ref       = optional(string)
    flake_attr      = optional(string)
    flake_dir       = optional(string, "/etc/nixos")
    log_dir         = optional(string, "/var/log/coder-nixos")
    config_override = optional(any, {})
  })
  default = {}

  validation {
    condition     = !var.nixos.enabled || (var.nixos.flake_ref != null && var.nixos.flake_attr != null)
    error_message = "nixos.flake_ref and nixos.flake_attr are required when nixos.enabled is true."
  }
  validation {
    condition     = startswith(var.nixos.flake_dir, "/") && abspath(var.nixos.flake_dir) != "/"
    error_message = "nixos.flake_dir must be an absolute path other than /."
  }
}

locals {
  flake_url    = try(replace(replace(var.nixos.flake_ref, "/^git\\+/", ""), "/\\?.*$/", ""), "")
  flake_branch = try(regex("[?&]ref=([^&#]+)", var.nixos.flake_ref)[0], "")
}

output "boot_script" {
  description = "Root-run boot script applying the flake; null when nixos is disabled."
  value = !var.nixos.enabled ? null : templatefile("${path.module}/scripts/nixos/boot.sh.tftpl", {
    ARG_FLAKE_URL    = local.flake_url
    ARG_FLAKE_BRANCH = local.flake_branch
    ARG_FLAKE_ATTR   = var.nixos.flake_attr
    ARG_FLAKE_DIR    = var.nixos.flake_dir
    ARG_LOG_DIR      = var.nixos.log_dir
    ARG_NIX_CONF     = local.nix_conf.nixos
    REBUILD_SH       = file("${path.module}/scripts/nixos/rebuild.sh")
  })
}

output "flake_uri" {
  description = "Flake reference built, normalized for display; null when nixos is disabled."
  value       = !var.nixos.enabled ? null : "${local.flake_url}${local.flake_branch == "" ? "" : "?ref=${local.flake_branch}"}#${var.nixos.flake_attr}"
}

output "log_dir" {
  description = "Rebuild transcript directory; null when nixos is disabled."
  value       = var.nixos.enabled ? var.nixos.log_dir : null
}

output "version_command" {
  description = "Shell snippet for agent metadata: running NixOS version, flagging a staged generation; null when nixos is disabled."
  value       = !var.nixos.enabled ? null : <<-EOT
    version=$(nixos-version 2>/dev/null || echo unknown)
    if [ "$(readlink -f /run/current-system)" = "$(readlink -f /nix/var/nix/profiles/system)" ]; then
      echo "$version"
    else
      echo "$version (restart to apply update)"
    fi
  EOT
}
