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
  description = "The ID of a Coder agent. Required when `develop.path` is set, for the `nix develop` app; `nixos` runs before the agent exists and does not need it."
  type        = string
  default     = null
}

variable "icon" {
  description = "Icon for the apps this module creates."
  type        = string
  default     = "/icon/nix.svg"
}
