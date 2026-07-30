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

variable "python_version" {
  description = "Python version to install and select globally with pyenv."
  type        = string
  default     = "3.13.5"

  validation {
    condition     = can(regex("^\\d+\\.\\d+\\.\\d+$", var.python_version))
    error_message = "python_version must be an exact semantic version such as 3.13.5."
  }
}

variable "build_packages" {
  description = "APT packages required to build Python with pyenv."
  type        = list(string)
  default = [
    "build-essential",
    "curl",
    "git",
    "libbz2-dev",
    "libffi-dev",
    "liblzma-dev",
    "libncursesw5-dev",
    "libreadline-dev",
    "libsqlite3-dev",
    "libssl-dev",
    "libxml2-dev",
    "libxmlsec1-dev",
    "tk-dev",
    "xz-utils",
    "zlib1g-dev",
  ]
}

variable "pyenv_git_ref" {
  description = "Git branch or tag of pyenv to install."
  type        = string
  default     = "master"

  validation {
    condition     = can(regex("^[0-9A-Za-z][0-9A-Za-z._/-]*$", var.pyenv_git_ref))
    error_message = "pyenv_git_ref must be a valid Git branch or tag name."
  }
}

variable "icon" {
  description = "Icon to use for the Python install scripts."
  type        = string
  default     = "/icon/python.svg"
}

variable "update_packages" {
  description = "Run apt-get update before installing missing packages."
  type        = bool
  default     = true
}

locals {
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_BUILD_PACKAGES_B64 = base64encode(join("\n", var.build_packages))
    ARG_PYTHON_VERSION     = var.python_version
    ARG_PYENV_GIT_REF      = var.pyenv_git_ref
    ARG_UPDATE_PACKAGES    = tostring(var.update_packages)
  })
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/.coder-modules/attractivetoad/python"
  display_name_prefix = "Python"
  icon                = var.icon
  install_script      = local.install_script
}

output "scripts" {
  description = "Ordered list of coder exp sync names produced by this module, in run order."
  value       = module.coder_utils.scripts
}
