terraform {
  required_version = ">= 1.9"
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.15"
    }
  }
}

variable "agent_id" {
  description = "Coder agent ID, required when develop is enabled."
  type        = string
  default     = null
}

variable "icon" {
  description = "Icon for the module's apps and scripts."
  type        = string
  default     = "/icon/nix.svg"
}

variable "config" {
  description = "Shared nix.conf settings. Each mode's config_override replaces individual keys. Lists are space-joined; prefer extra-* keys to append to existing settings. On NixOS, prefer the flake's nix.settings for persistent settings."
  type        = any
  default     = {}
}

locals {
  # Nix accumulates repeated extra-* lines, so required features are appended.
  nix_conf = {
    for mode, override in { nixos = var.nixos.config_override, develop = var.develop.config_override } :
    mode => join("\n", concat(
      [for k, v in merge(var.config, override) : "${k} = ${join(" ", flatten([v]))}"],
      ["extra-experimental-features = nix-command flakes"],
    ))
  }
}
