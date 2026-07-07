terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
    }
  }
}

locals {
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    PYTHON_PACKAGES = join(" ", var.python_packages)
    UPDATE_PACKAGES = tostring(var.update_packages)
  })
}

variable "agent_id" {
  description = "The ID of a Coder agent."
  type        = string
}

variable "python_packages" {
  description = "APT packages to install for Python support."
  type        = list(string)
  default     = ["python3", "python3-pip", "python3-venv", "python-is-python3"]
}

variable "pre_install_script" {
  description = "Optional script to run before installing Python packages."
  type        = string
  default     = null
}

variable "post_install_script" {
  description = "Optional script to run after installing Python packages."
  type        = string
  default     = null
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

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/.coder-modules/thezoker/python"
  display_name_prefix = "Python"
  icon                = var.icon
  pre_install_script  = var.pre_install_script
  install_script      = local.install_script
  post_install_script = var.post_install_script
}

output "scripts" {
  description = "Ordered list of coder exp sync names produced by this module, in run order."
  value       = module.coder_utils.scripts
}
