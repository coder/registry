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

variable "python_packages" {
  description = "APT packages to install for Python support."
  type        = list(string)
  default     = ["python3", "python3-pip", "python3-venv"]
}

variable "create_python_alias" {
  description = "Create a python command that points to python3 when python is missing."
  type        = bool
  default     = true
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

resource "coder_script" "install" {
  agent_id           = var.agent_id
  display_name       = "Python: Install Script"
  icon               = var.icon
  run_on_start       = true
  start_blocks_login = true
  script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    PYTHON_PACKAGES     = join(" ", var.python_packages)
    UPDATE_PACKAGES     = tostring(var.update_packages)
    CREATE_PYTHON_ALIAS = tostring(var.create_python_alias)
  })
}

output "scripts" {
  description = "Ordered list of script names produced by this module, in run order."
  value       = ["attractivetoad-python-install"]
}
