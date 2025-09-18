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

variable "nextflow_version" {
  type        = string
  description = "Nextflow version"
  default     = "25.04.7"
}

variable "project_path" {
  type        = string
  description = "The path to Nextflow project, it will be mounted in the container."
}

variable "http_server_port" {
  type        = number
  description = "The port to run HTTP server on."
  default     = 9876
}

variable "http_server_reports_dir" {
  type        = string
  description = "Subdirectory for HTTP server reports, relative to the project path."
  default     = "reports"
}

variable "http_server_log_path" {
  type        = string
  description = "HTTP server logs"
  default     = "/tmp/nextflow_reports.log"
}

variable "stub_run" {
  type        = bool
  description = "Execute a stub run?"
  default     = false
}

variable "stub_run_command" {
  type        = string
  description = "Nextflow command to be executed in the stub run."
  default     = "run rnaseq-nf -with-report reports/report.html -with-trace reports/trace.txt -with-timeline reports/timeline.html -with-dag reports/flowchart.png"
}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  default     = null
}

variable "share" {
  type    = string
  default = "owner"
  validation {
    condition     = var.share == "owner" || var.share == "authenticated" || var.share == "public"
    error_message = "Incorrect value. Please set either 'owner', 'authenticated', or 'public'."
  }
}

variable "group" {
  type        = string
  description = "The name of a group that this app belongs to."
  default     = null
}

resource "coder_script" "nextflow" {
  agent_id     = var.agent_id
  display_name = "nextflow"
  icon         = "/icon/nextflow.svg"
  script = templatefile("${path.module}/run.sh", {
    NEXTFLOW_VERSION : var.nextflow_version,
    PROJECT_PATH : var.project_path,
    HTTP_SERVER_PORT : var.http_server_port,
    HTTP_SERVER_REPORTS_DIR : var.http_server_reports_dir,
    HTTP_SERVER_LOG_PATH : var.http_server_log_path,
    STUB_RUN : var.stub_run,
    STUB_RUN_COMMAND : var.stub_run_command,
  })
  run_on_start = true
}

resource "coder_app" "nextflow" {
  agent_id     = var.agent_id
  slug         = "nextflow-reports"
  display_name = "Nextflow Reports"
  url          = "http://localhost:${var.http_server_port}"
  icon         = "/icon/nextflow.svg"
  subdomain    = true
  share        = var.share
  order        = var.order
  group        = var.group
}
