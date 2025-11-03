terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

locals {
  # A built-in icon like "/icon/code.svg" or a full URL of icon
  icon_url = "/icon/copyparty.svg"
  # a map of all possible values
  # options = {
  #   "Option 1" = {
  #     "name"  = "Option 1",
  #     "value" = "1"
  #     "icon"  = "/emojis/1.png"
  #   }
  #   "Option 2" = {
  #     "name"  = "Option 2",
  #     "value" = "2"
  #     "icon"  = "/emojis/2.png"
  #   }
  # }
}

# Add required variables for your modules and remove any unneeded variables
variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "log_path" {
  type        = string
  description = "The path to log copyparty to."
  default     = "/tmp/copyparty.log"
}

variable "port" {
  type        = number
  description = "ports to listen on (comma/range); ignored for unix-sockets (default: 3923)"
  default     = 3923
}

variable "slug" {
  type        = string
  description = "The slug for the copyparty application."
  default     = "copyparty"
}

variable "display_name" {
  type        = string
  description = "The display name for the copyparty application."
  default     = "copyparty"
}

variable "group" {
  type        = string
  description = "The name of a group that this app belongs to."
  default     = null
}

variable "open_in" {
  type        = string
  description = <<-EOT
    Determines where the app will be opened. Valid values are `"tab"` and `"slim-window" (default)`.
    `"tab"` opens in a new tab in the same browser window.
    `"slim-window"` opens a new browser window without navigation controls.
  EOT
  default     = "slim-window"
  validation {
    condition     = contains(["tab", "slim-window"], var.open_in)
    error_message = "The 'open_in' variable must be one of: 'tab', 'slim-window'."
  }
}

variable "subdomain" {
  type        = bool
  description = <<-EOT
    Determines whether the app will be accessed via it's own subdomain or whether it will be accessed via a path on Coder.
    If wildcards have not been setup by the administrator then apps with "subdomain" set to true will not be accessible.
  EOT
  default     = false
}

variable "share" {
  type    = string
  default = "owner"
  validation {
    condition     = var.share == "owner" || var.share == "authenticated" || var.share == "public"
    error_message = "Incorrect value. Please set either 'owner', 'authenticated', or 'public'."
  }
}

# variable "mutable" {
#   type        = bool
#   description = "Whether the parameter is mutable."
#   default     = true
# }

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  default     = null
}
# Add other variables here

variable "pinned_version" {
  type        = string
  description = "Install a specific version in semver format (v1.19.16)."
  default     = ""
}

variable "arguments" {
  type        = list(string)
  description = "A list of arguments to pass to the application."
  default     = []
}


resource "coder_script" "copyparty" {
  agent_id     = var.agent_id
  display_name = "copyparty"
  icon         = local.icon_url
  script = templatefile("${path.module}/run.sh", {
    LOG_PATH : var.log_path,
    PORT : var.port,
    PINNED_VERSION : var.pinned_version,
    ARGUMENTS : join(" ", formatlist("\"%s\"", var.arguments)),
  })
  run_on_start = true
  run_on_stop  = false
}

resource "coder_app" "copyparty" {
  agent_id     = var.agent_id
  slug         = var.slug
  display_name = var.display_name
  url          = "http://localhost:${var.port}"
  icon         = local.icon_url
  subdomain    = var.subdomain
  share        = var.share
  order        = var.order
  group        = var.group
  open_in      = var.open_in

  # Remove if the app does not have a healthcheck endpoint
  healthcheck {
    url       = "http://localhost:${var.port}"
    interval  = 5
    threshold = 6
  }
}

# data "coder_parameter" "copyparty" {
#   type         = "list(string)"
#   name         = "copyparty"
#   display_name = "copyparty"
#   icon         = local.icon_url
#   mutable      = var.mutable
#   default      = local.options["Option 1"]["value"]

#   dynamic "option" {
#     for_each = local.options
#     content {
#       icon  = option.value.icon
#       name  = option.value.name
#       value = option.value.value
#     }
#   }
# }
