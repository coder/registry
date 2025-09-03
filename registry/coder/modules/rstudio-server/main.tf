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

variable "docker_socket" {
  type        = string
  description = "(Optional) Docker socket URI"
  default     = ""
}

variable "rstudio_server_version" {
  type        = string
  description = "RStudio Server version"
  default     = "4.5.1"
}

variable "disable_auth" {
  type        = bool
  description = "Disable auth"
  default     = true
}

variable "rstudio_user" {
  type        = string
  description = "RStudio user"
  default     = "rstudio"
  sensitive   = true
}

variable "rstudio_password" {
  type        = string
  description = "RStudio password"
  default     = "rstudio"
  sensitive   = true
}

variable "project_path" {
  type        = string
  description = "The path to RStudio project, it will be mounted in the container."
  default     = null
}

variable "port" {
  type        = number
  description = "The port to run rstudio-server on."
  default     = 8787
}

variable "enable_renv" {
  type        = bool
  description = "If renv.lock exists, renv will restore the environment and install dependencies"
  default     = true
}

variable "renv_cache_volume" {
  type        = string
  description = "The name of the volume used by Renv to preserve dependencies between container restarts"
  default     = "renv-cache-volume"
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

resource "coder_script" "rstudio-server" {
  agent_id     = var.agent_id
  display_name = "rstudio-server"
  icon         = "/icon/rstudio.svg"
  script = templatefile("${path.module}/run.sh", {
    DOCKER_HOST : var.docker_socket,
    SERVER_VERSION : var.rstudio_server_version,
    DISABLE_AUTH : var.disable_auth,
    RSTUDIO_USER : var.rstudio_user,
    RSTUDIO_PASSWORD : var.rstudio_password,
    PROJECT_PATH : var.project_path,
    PORT : var.port,
    ENABLE_RENV : var.enable_renv,
    RENV_CACHE_VOLUME : var.renv_cache_volume,
  })
  run_on_start = true
}

resource "coder_app" "rstudio-server" {
  agent_id     = var.agent_id
  slug         = "rstudio-server"
  display_name = "RStudio Server"
  url          = "http://localhost:${var.port}"
  icon         = "/icon/rstudio.svg"
  subdomain    = true
  share        = var.share
  order        = var.order
  group        = var.group
}
