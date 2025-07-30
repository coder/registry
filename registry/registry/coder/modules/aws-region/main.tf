terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.12"
    }
  }
}

variable "display_name" {
  default     = "AWS Region"
  description = "The display name of the parameter."
  type        = string
}

variable "description" {
  default     = "The region to deploy workspace infrastructure."
  description = "The description of the parameter."
  type        = string
}

variable "default" {
  default     = ""
  description = "The default region to use if no region is specified."
  type        = string
}

variable "mutable" {
  default     = false
  description = "Whether the parameter can be changed after creation."
  type        = bool
}

variable "custom_names" {
  default     = {}
  description = "A map of custom display names for region IDs."
  type        = map(string)
}

variable "custom_icons" {
  default     = {}
  description = "A map of custom icons for region IDs."
  type        = map(string)
}

variable "exclude" {
  default     = []
  description = "A list of region IDs to exclude."
  type        = list(string)
}

variable "coder_parameter_order" {
  type        = number
  description = "The order determines the position of a template parameter in the UI/CLI presentation. The lowest order is shown first and parameters with equal order are sorted by name (ascending order)."
  default     = null
}

locals {
  # This is a static list because the regions don't change _that_
  # frequently and including the `aws_regions` data source requires
  # the provider, which requires a region.
  regions = {
    "af-south-1" = {
      name = "Africa (Cape Town)"
      icon = "/emojis/1f1ff-1f1e6.png"
    }
    "ap-east-1" = {
      name = "Asia Pacific (Hong Kong)"
      icon = "/emojis/1f1ed-1f1f0.png"
    }
    "ap-northeast-1" = {
      name = "Asia Pacific (Tokyo)"
      icon = "/emojis/1f1ef-1f1f5.png"
    }
    "ap-northeast-2" = {
      name = "Asia Pacific (Seoul)"
      icon = "/emojis/1f1f0-1f1f7.png"
    }
    "ap-northeast-3" = {
      name = "Asia Pacific (Osaka)"
      icon = "/emojis/1f1ef-1f1f5.png"
    }
    "ap-south-1" = {
      name = "Asia Pacific (Mumbai)"
      icon = "/emojis/1f1ee-1f1f3.png"
    }
    "ap-south-2" = {
      name = "Asia Pacific (Hyderabad)"
      icon = "/emojis/1f1ee-1f1f3.png"
    }
    "ap-southeast-1" = {
      name = "Asia Pacific (Singapore)"
      icon = "/emojis/1f1f8-1f1ec.png"
    }
    "ap-southeast-2" = {
      name = "Asia Pacific (Sydney)"
      icon = "/emojis/1f1e6-1f1fa.png"
    }
    "ap-southeast-3" = {
      name = "Asia Pacific (Jakarta)"
      icon = "/emojis/1f1ee-1f1e9.png"
    }
    "ap-southeast-4" = {
      name = "Asia Pacific (Melbourne)"
      icon = "/emojis/1f1e6-1f1fa.png"
    }
    "ca-central-1" = {
      name = "Canada (Central)"
      icon = "/emojis/1f1e8-1f1e6.png"
    }
    "ca-west-1" = {
      name = "Canada West (Calgary)"
      icon = "/emojis/1f1e8-1f1e6.png"
    }
    "eu-central-1" = {
      name = "EU (Frankfurt)"
      icon = "/emojis/1f1ea-1f1fa.png"
    }
    "eu-central-2" = {
      name = "Europe (Zurich)"
      icon = "/emojis/1f1ea-1f1fa.png"
    }
    "eu-north-1" = {
      name = "EU (Stockholm)"
      icon = "/emojis/1f1ea-1f1fa.png"
    }
    "eu-south-1" = {
      name = "Europe (Milan)"
      icon = "/emojis/1f1ea-1f1fa.png"
    }
    "eu-south-2" = {
      name = "Europe (Spain)"
      icon = "/emojis/1f1ea-1f1fa.png"
    }
    "eu-west-1" = {
      name = "EU (Ireland)"
      icon = "/emojis/1f1ea-1f1fa.png"
    }
    "eu-west-2" = {
      name = "EU (London)"
      icon = "/emojis/1f1ea-1f1fa.png"
    }
    "eu-west-3" = {
      name = "EU (Paris)"
      icon = "/emojis/1f1ea-1f1fa.png"
    }
    "il-central-1" = {
      name = "Israel (Tel Aviv)"
      icon = "/emojis/1f1ee-1f1f1.png"
    }
    "me-south-1" = {
      name = "Middle East (Bahrain)"
      icon = "/emojis/1f1e7-1f1ed.png"
    }
    "sa-east-1" = {
      name = "South America (São Paulo)"
      icon = "/emojis/1f1e7-1f1f7.png"
    }
    "us-east-1" = {
      name = "US East (N. Virginia)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-east-2" = {
      name = "US East (Ohio)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-west-1" = {
      name = "US West (N. California)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "us-west-2" = {
      name = "US West (Oregon)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
  }
}

data "coder_parameter" "region" {
  name         = "aws_region"
  display_name = var.display_name
  description  = var.description
  default      = var.default == "" ? null : var.default
  order        = var.coder_parameter_order
  mutable      = var.mutable
  dynamic "option" {
    for_each = { for k, v in local.regions : k => v if !(contains(var.exclude, k)) }
    content {
      name  = try(var.custom_names[option.key], option.value.name)
      icon  = try(var.custom_icons[option.key], option.value.icon)
      value = option.key
    }
  }
}

output "value" {
  value = data.coder_parameter.region.value
}