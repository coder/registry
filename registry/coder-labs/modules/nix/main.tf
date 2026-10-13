terraform {
  required_version = ">= 1.9"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

# Shared inputs. Each mode lives in its own file:
# - nixos.tf:   rebuild the whole system from a flake on boot (`nixos`)
# - develop.tf: enter a `nix develop` shell from a project flake (`develop`)

variable "agent_id" {
  description = "The ID of a Coder agent. Required when `develop` is enabled; `nixos` runs before the agent exists and does not need it."
  type        = string
  default     = null
}

variable "icon" {
  description = "Icon for the apps and scripts this module creates."
  type        = string
  default     = "/icon/nix.svg"
}

variable "config" {
  description = <<-EOT
    nix.conf settings shared by `nixos` and `develop`. Each mode can replace
    individual keys with its own `config_override`. Lists are joined with
    spaces; booleans become `true`/`false`. Prefer `extra-*` keys (e.g.
    `extra-substituters`) so values are appended to what NixOS or the Nix
    installer already configured instead of replacing it.

    On NixOS, if you control the flake, prefer its `nix.settings`; this is for
    when you don't.
  EOT
  type        = any
  default     = {}

  # Same rule as the `config_override` validations in nixos.tf and develop.tf.
  validation {
    condition     = try(alltrue([for k, v in var.config : can(regex("^[a-z][a-z0-9-]*$", k)) && (can(regex("^[^[:cntrl:]]*$", v)) || (can(tolist(v)) && can([for x in tolist(v) : regex("^[^[:cntrl:]]*$", x)])))]), false)
    error_message = "config must be a map of nix.conf setting names (lowercase letters, digits, dashes) to strings, numbers, booleans or lists of strings, without control characters."
  }
}

locals {
  # Settings that only the nix-daemon honours from trusted callers. When
  # `nixos` manages the daemon they are already applied there, and an
  # untrusted `nix` client sending them again only triggers "ignoring the
  # client-specified setting ..." warnings.
  daemon_only_settings = toset(flatten([
    for k in ["trusted-public-keys", "trusted-substituters", "trusted-users"] : [k, "extra-${k}"]
  ]))
}
