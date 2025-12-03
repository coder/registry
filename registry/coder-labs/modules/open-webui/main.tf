terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

# Add required variables for your modules and remove any unneeded variables
variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "http_server_log_path" {
  type        = string
  description = "The path to log Open WebUI to."
  default     = "/tmp/open-webui.log"
}

variable "http_server_port" {
  type        = number
  description = "The port to run Open WebUI on."
  default     = 7800
}

variable "open_webui_version" {
  type        = string
  description = "The version of Open WebUI to install."
  default     = "0.6.40"
}

variable "data_dir" {
  type        = string
  description = "The directory where Open WebUI stores its data (database, uploads, vector_db, cache)."
  default     = "$HOME/.open-webui"
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

variable "group" {
  type        = string
  description = "The name of a group that this app belongs to."
  default     = null
}

resource "coder_script" "open-webui" {
  agent_id     = var.agent_id
  display_name = "open-webui"
  icon         = "/icon/openwebui.svg"
  script = templatefile("${path.module}/run.sh", {
    HTTP_SERVER_LOG_PATH : var.http_server_log_path,
    HTTP_SERVER_PORT : var.http_server_port,
    VERSION : var.open_webui_version,
    DATA_DIR : var.data_dir,
  })
  run_on_start = true
}

resource "coder_app" "open-webui" {
  agent_id     = var.agent_id
  slug         = "open-webui"
  display_name = "Open WebUI"
  url          = "http://localhost:${var.http_server_port}"
  icon         = "/icon/openwebui.svg"
  subdomain    = true
  share        = var.share
  order        = var.order
  group        = var.group
}
