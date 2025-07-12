terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.23"
    }
  }
}

variable "default" {
  type        = string
  description = "The default region to select"
  default     = "ams3"
}

variable "mutable" {
  type        = bool
  description = "Whether the region can be changed after workspace creation"
  default     = false
}

variable "name" {
  type        = string
  description = "The name of the parameter"
  default     = "region"
}

variable "display_name" {
  type        = string
  description = "The display name of the parameter"
  default     = "Region"
}

variable "description" {
  type        = string
  description = "The description of the parameter"
  default     = "This is the region where your workspace will be created."
}

variable "icon" {
  type        = string
  description = "The icon to display for the parameter"
  default     = "/emojis/1f30e.png"
}

data "coder_parameter" "region" {
  name         = var.name
  display_name = var.display_name
  description  = var.description
  icon         = var.icon
  type         = "string"
  default      = var.default
  mutable      = var.mutable
  # nyc1, sfo1, and ams2 regions were excluded because they do not support volumes, which are used to persist data while decreasing cost
  option {
    name  = "Canada (Toronto)"
    value = "tor1"
    icon  = "/emojis/1f1e8-1f1e6.png"
  }
  option {
    name  = "Germany (Frankfurt)"
    value = "fra1"
    icon  = "/emojis/1f1e9-1f1ea.png"
  }
  option {
    name  = "India (Bangalore)"
    value = "blr1"
    icon  = "/emojis/1f1ee-1f1f3.png"
  }
  option {
    name  = "Netherlands (Amsterdam)"
    value = "ams3"
    icon  = "/emojis/1f1f3-1f1f1.png"
  }
  option {
    name  = "Singapore"
    value = "sgp1"
    icon  = "/emojis/1f1f8-1f1ec.png"
  }
  option {
    name  = "United Kingdom (London)"
    value = "lon1"
    icon  = "/emojis/1f1ec-1f1e7.png"
  }
  option {
    name  = "United States (California - 2)"
    value = "sfo2"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "United States (California - 3)"
    value = "sfo3"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "United States (New York - 1)"
    value = "nyc1"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "United States (New York - 3)"
    value = "nyc3"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
}

output "value" {
  description = "The selected region value"
  value       = data.coder_parameter.region.value
}

output "name" {
  description = "The selected region name"
  value       = data.coder_parameter.region.name
}

output "display_name" {
  description = "The selected region display name"
  value       = data.coder_parameter.region.display_name
}