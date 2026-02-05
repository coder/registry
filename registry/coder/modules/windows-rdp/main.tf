terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

variable "display_name" {
  type        = string
  description = "The display name for the Web RDP application."
  default     = "Web RDP"
}

variable "slug" {
  type        = string
  description = "The slug for the Web RDP application."
  default     = "web-rdp"
}

variable "icon" {
  type        = string
  description = "The icon for the Web RDP application."
  default     = "/icon/desktop.svg"
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

variable "share" {
  type    = string
  default = "owner"
  validation {
    condition     = var.share == "owner" || var.share == "authenticated" || var.share == "public"
    error_message = "Incorrect value. Please set either 'owner', 'authenticated', or 'public'."
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "admin_username" {
  type    = string
  default = "Administrator"
}

variable "admin_password" {
  type      = string
  default   = "coderRDP!"
  sensitive = true
}

variable "devolutions_gateway_version" {
  type        = string
  default     = "latest"
  description = "Version of Devolutions Gateway to install. Use 'latest' for the most recent version, or specify a version like '2025.3.2'."
}

variable "keepalive" {
  type        = bool
  default     = false
  description = "Enable automatic workspace session extension while RDP is active. When enabled, the workspace will remain active as long as an RDP connection exists."
}

variable "keepalive_interval" {
  type        = number
  default     = 300
  description = "Interval in seconds between RDP connection checks when keepalive is enabled. Default is 300 seconds (5 minutes)."
  validation {
    condition     = var.keepalive_interval >= 60 && var.keepalive_interval <= 3600
    error_message = "keepalive_interval must be between 60 and 3600 seconds."
  }
}

resource "coder_script" "windows-rdp" {
  agent_id     = var.agent_id
  display_name = "windows-rdp"
  icon         = "/icon/rdp.svg"

  script = templatefile("${path.module}/powershell-installation-script.tftpl", {
    admin_username              = var.admin_username
    admin_password              = var.admin_password
    devolutions_gateway_version = var.devolutions_gateway_version

    # Wanted to have this be in the powershell template file, but Terraform
    # doesn't allow recursive calls to the templatefile function. Have to feed
    # results of the JS template replace into the powershell template
    patch_file_contents = templatefile("${path.module}/devolutions-patch.js", {
      CODER_USERNAME = var.admin_username
      CODER_PASSWORD = var.admin_password
    })
  })

  run_on_start = true
}

resource "coder_app" "windows-rdp" {
  agent_id     = var.agent_id
  share        = var.share
  slug         = var.slug
  display_name = var.display_name
  url          = "http://localhost:7171"
  icon         = var.icon
  subdomain    = true
  order        = var.order
  group        = var.group

  healthcheck {
    url       = "http://localhost:7171"
    interval  = 5
    threshold = 15
  }
}

resource "coder_script" "windows-rdp-keepalive" {
  count        = var.keepalive ? 1 : 0
  agent_id     = var.agent_id
  display_name = "windows-rdp-keepalive"
  icon         = "/icon/rdp.svg"

  script = templatefile("${path.module}/keepalive-script.tftpl", {
    keepalive_interval = var.keepalive_interval
  })

  run_on_start       = true
  start_blocks_login = false
}

resource "coder_app" "rdp-docs" {
  agent_id     = var.agent_id
  display_name = "Local RDP Docs"
  slug         = "rdp-docs"
  icon         = "/icon/windows.svg"
  url          = "https://coder.com/docs/user-guides/workspace-access/remote-desktops#rdp"
  external     = true
}
