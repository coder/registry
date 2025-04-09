terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.17"
    }
  }
}

# Add required variables for your modules and remove any unneeded variables
variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "log_path" {
  type        = string
  description = "The path to log airflow to."
  default     = "/tmp/airflow.log"
}

variable "port" {
  type        = number
  description = "The port to run airflow on."
  default     = 8080
}

variable "share" {
  type    = string
  default = "owner"
  validation {
    condition     = var.share == "owner" || var.share == "authenticated" || var.share == "public"
    error_message = "Incorrect value. Please set either 'owner', 'authenticated', or 'public'."
  }
}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  default     = null
}

resource "coder_script" "airflow" {
  agent_id     = var.agent_id
  display_name = "airflow"
  icon         = "/icon/apache-guacamole.svg"
  script = templatefile("${path.module}/run.sh", {
    LOG_PATH : var.log_path,
    PORT : var.port
  })
  run_on_start = true
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
