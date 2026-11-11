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

variable "log_path" {
  description = "The path to log airflow to."
  type        = string
  default     = "$HOME/.coder-modules/nataindata/apache-airflow/logs/webserver.log"
}

variable "port" {
  description = "The port to run airflow on."
  type        = number
  default     = 8080

  validation {
    condition     = var.port >= 1 && var.port <= 65535 && floor(var.port) == var.port
    error_message = "The Airflow port must be an integer between 1 and 65535."
  }
}

variable "share" {
  description = "Who can access the Airflow app. The Airflow login is still required."
  type        = string
  default     = "owner"
  validation {
    condition     = var.share == "owner" || var.share == "authenticated" || var.share == "public"
    error_message = "Incorrect value. Please set either 'owner', 'authenticated', or 'public'."
  }
}

variable "order" {
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  type        = number
  default     = null
}

variable "airflow_version" {
  description = "Airflow 2 release to install. The workspace Python version must be supported by this release."
  type        = string
  default     = "2.11.0"

  validation {
    condition     = can(regex("^2\\.([7-9]|[1-9][0-9]+)\\.[0-9]+$", var.airflow_version))
    error_message = "Use an exact Airflow 2.7 or later 2.x release (for example, 2.11.0). Airflow 3 uses a different server CLI."
  }
}

locals {
  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    AIRFLOW_VERSION = var.airflow_version
  })
  start_script = templatefile("${path.module}/scripts/start.sh.tftpl", {
    LOG_PATH = base64encode(var.log_path)
    PORT     = var.port
  })
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = "$HOME/.coder-modules/nataindata/apache-airflow"
  display_name_prefix = "airflow"
  icon                = "/icon/apache-guacamole.svg"
  install_script      = local.install_script
  start_script        = local.start_script
}

output "scripts" {
  description = "Ordered script synchronization names for the Airflow install and start pipeline."
  value       = module.coder_utils.scripts
}

resource "coder_app" "airflow" {
  agent_id     = var.agent_id
  slug         = "airflow"
  display_name = "airflow"
  url          = "http://localhost:${var.port}"
  icon         = "/icon/apache-guacamole.svg"
  subdomain    = true
  share        = var.share
  order        = var.order
}
