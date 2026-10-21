terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
    }
  }
}

variable "agent_id" {
  description = "The ID of a Coder agent."
  type        = string
}

variable "repo_dir" {
  description = "Absolute path to the repository where `mise install` should run. Typically wired to `module.git-clone.repo_dir`."
  type        = string
}

variable "mise_trust" {
  description = "Whether to run `mise trust` on the repository before `mise install`. Required for projects that ship a `.mise.toml`."
  type        = bool
  default     = true
}

variable "activate_shells" {
  description = "Shell rc files to append `mise activate` to. Pass an empty list to skip activation."
  type        = list(string)
  default     = ["bash", "zsh"]

  validation {
    condition     = alltrue([for s in var.activate_shells : contains(["bash", "zsh"], s)])
    error_message = "activate_shells entries must be one of: bash, zsh."
  }
}

variable "install_dir" {
  description = "Directory to install the `mise` binary into. Passed to the mise installer as `MISE_INSTALL_PATH`'s parent."
  type        = string
  default     = "$HOME/.local/bin"
}

variable "install_mise" {
  description = "Whether to download and install `mise`. Set to false in restricted or air-gapped environments where the workspace image already ships `mise`; the module will then only configure shell activation and run `mise install`."
  type        = bool
  default     = true
}

variable "install_url" {
  description = "URL of the mise installer script. Override to point at an internal mirror in restricted environments. Ignored when `install_mise = false`."
  type        = string
  default     = "https://mise.run"
}

variable "mise_version" {
  description = "Pin the mise release to install by setting `MISE_VERSION` before invoking the installer (e.g. `\"v2024.9.0\"`). Empty means install the latest release advertised by `install_url`. Ignored when `install_mise = false`."
  type        = string
  default     = ""
}

variable "mise_bin" {
  description = "Absolute path to a pre-installed `mise` binary (e.g. `/opt/mise/bin/mise` baked into a workspace image). When non-empty, its directory is prepended to PATH so this module and downstream scripts pick it up. Combine with `install_mise = false` to fully opt out of downloading."
  type        = string
  default     = ""
}

variable "wait_seconds" {
  description = "Maximum seconds to wait for `repo_dir/.git` to appear (i.e. for the git-clone module to finish) before skipping `mise install`."
  type        = number
  default     = 300

  validation {
    condition     = var.wait_seconds >= 0
    error_message = "wait_seconds must be non-negative."
  }
}

variable "icon" {
  description = "Icon shown in the Coder UI for the coder_script resources this module creates."
  type        = string
  default     = "/icon/code.svg"
}

locals {
  module_directory = "$HOME/.coder-modules/droopy4096/mise-install"

  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL_DIR     = var.install_dir
    ARG_ACTIVATE_SHELLS = join(" ", var.activate_shells)
    ARG_INSTALL_MISE    = tostring(var.install_mise)
    ARG_INSTALL_URL     = var.install_url
    ARG_MISE_VERSION    = var.mise_version
    ARG_MISE_BIN        = var.mise_bin
  })

  post_install_script = templatefile("${path.module}/scripts/post_install.sh.tftpl", {
    ARG_REPO_DIR     = var.repo_dir
    ARG_MISE_TRUST   = tostring(var.mise_trust)
    ARG_INSTALL_DIR  = var.install_dir
    ARG_MISE_BIN     = var.mise_bin
    ARG_WAIT_SECONDS = tostring(var.wait_seconds)
  })
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = local.module_directory
  display_name_prefix = "mise"
  icon                = var.icon
  install_script      = local.install_script
  post_install_script = local.post_install_script
}

output "repo_dir" {
  description = "The repository directory where `mise install` was run."
  value       = var.repo_dir
}

output "scripts" {
  description = "Ordered list of `coder exp sync` names produced by this module, in run order."
  value       = module.coder_utils.scripts
}
