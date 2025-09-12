terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

variable "log_path" {
  type        = string
  description = "The path to log rustdesk to."
  default     = "/tmp/rustdesk.log"
}

variable "agent_id" {
  description = "Attach RustDesk setup to this agent"
  type        = string
}

variable "order" {
  description = "Run order among scripts/apps"
  type        = number
  default     = 1
}

# Optional knobs passed as env (you can expose these as variables too)
variable "rustdesk_password" {
  description = "If empty, the script will generate one"
  type        = string
  default     = ""
  sensitive   = true
}

variable "xvfb_resolution" {
  description = "Xvfb screen size/depth"
  type        = string
  default     = "1024x768x16"
}

variable "rustdesk_version" {
  description = "RustDesk version to install (use 'latest' for most recent release)"
  type        = string
  default     = "latest"
}

resource "coder_script" "rustdesk" {
  agent_id     = var.agent_id
  display_name = "RustDesk"
  run_on_start = true

  # Prepend env as bash exports, then append the script file literally.
  script = <<-EOT
    # --- module-provided env knobs ---
    export RUSTDESK_PASSWORD="${var.rustdesk_password}"
    export XVFB_RESOLUTION="${var.xvfb_resolution}"
    export RUSTDESK_VERSION="${var.rustdesk_version}"
    # ---------------------------------

${file("${path.module}/run.sh")}
  EOT
}

resource "coder_app" "rustdesk" {
  agent_id     = var.agent_id
  slug         = "rustdesk"
  display_name = "Rustdesk"
  url          = "https://rustdesk.com/web"
  icon         = "/icon/rustdesk.svg"
  order        = var.order
  external     = true
}

