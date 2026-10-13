# `develop`: enter a `nix develop` shell from a project flake, optionally as a
# Coder app.

variable "develop" {
  description = <<-EOT
    Enter a `nix develop` shell from a project flake.

    - `enabled`: produce `develop_command`. Defaults to `false`.
    - `path`: directory containing the project's `flake.nix`. Absolute, or
      relative to the workspace user's home directory (`~/` is accepted). When
      set, a `nix develop` terminal app is added to the agent (requires
      `agent_id`).
    - `shell`: `devShells` attribute to enter; defaults to the flake's default
      shell.
    - `display_name`, `order`, `group`: presentation of the app.
  EOT
  type = object({
    enabled      = optional(bool, false)
    path         = optional(string)
    shell        = optional(string)
    display_name = optional(string, "Nix Develop")
    order        = optional(number)
    group        = optional(string)
  })
  default = {}

  validation {
    condition     = var.develop.enabled || var.nixos.enabled
    error_message = "At least one of nixos.enabled or develop.enabled must be true."
  }

  validation {
    condition     = alltrue([for v in [var.develop.path, var.develop.shell] : v == null ? true : (v != "" && !can(regex("[[:cntrl:]]", v)))])
    error_message = "develop.path and develop.shell must be non-empty and must not contain control characters."
  }
}

locals {
  develop_installable = var.develop.shell == null ? "." : ".#${var.develop.shell}"

  develop_nix = "nix --extra-experimental-features 'nix-command flakes' develop '${replace(local.develop_installable, "'", "'\\''")}'"

  # Values are POSIX single-quoted ('\'' escapes a quote). `~/x` and `x`
  # resolve from $HOME; absolute paths are used as-is.
  develop_path_relative = var.develop.path == null ? null : trimprefix(trimprefix(var.develop.path, "~/"), "./")
  develop_path_shell = (
    var.develop.path == null ? null :
    startswith(var.develop.path, "/") ? "'${replace(var.develop.path, "'", "'\\''")}'" :
    var.develop.path == "~" ? "\"$HOME\"" :
    "\"$HOME\"/'${replace(local.develop_path_relative, "'", "'\\''")}'"
  )

  develop_command = var.develop.path == null ? local.develop_nix : "cd ${local.develop_path_shell} && exec ${local.develop_nix}"
}

resource "coder_app" "develop" {
  count        = var.develop.enabled && var.develop.path != null ? 1 : 0
  agent_id     = var.agent_id
  slug         = "nix-develop"
  display_name = var.develop.display_name
  icon         = var.icon
  command      = local.develop_command
  order        = var.develop.order
  group        = var.develop.group

  lifecycle {
    precondition {
      condition     = var.agent_id != null && var.agent_id != ""
      error_message = "agent_id is required when develop.path is set."
    }
  }
}

output "develop_command" {
  description = "Shell command that enters the `nix develop` shell (from `develop.path` if set, otherwise the current directory). `null` when `develop.enabled` is false."
  value       = var.develop.enabled ? local.develop_command : null
}
