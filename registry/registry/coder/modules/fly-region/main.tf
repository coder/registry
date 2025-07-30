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
  default     = "Fly.io Region"
  description = "The display name of the parameter."
  type        = string
}

variable "description" {
  default     = "The region to deploy workspace infrastructure."
  description = "The description of the parameter."
  type        = string
}

variable "default" {
  default     = null
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

variable "regions" {
  default     = []
  description = "List of regions to include for region selection."
  type        = list(string)
}

locals {
  regions = {
    "ams" = {
      name      = "Amsterdam, Netherlands"
      gateway   = true
      paid_only = false
      icon      = "/emojis/1f1f3-1f1f1.png"
    }
    "arn" = {
      name      = "Stockholm, Sweden"
      gateway   = false
      paid_only = false
      icon      = "/emojis/1f1f8-1f1ea.png"
    }
    "atl" = {
      name      = "Atlanta, Georgia (US)"
      gateway   = false
      paid_only = false
      icon      = "/emojis/1f1fa-1f1f8.png"
    }
    "bog" = {
      name      = "Bogotá, Colombia"
      gateway   = false
      paid_only = false
      icon      = "/emojis/1f1e8-1f1f4.png"
    }
    "bom" = {
      name      = "Mumbai, India"
      gateway   = true
      paid_only = true
      icon      = "/emojis/1f1ee-1f1f3.png"
    }
    "bos" = {
      name      = "Boston, Massachusetts (US)"
      gateway   = false
      paid_only = false
      icon      = "/emojis/1f1fa-1f1f8.png"
    }
    "cdg" = {
      name      = "Paris, France"
      gateway   = true
      paid_only = false
      icon      = "/emojis/1f1eb-1f1f7.png"
    }
    "den" = {
      name      = "Denver, Colorado (US)"
      gateway   = false
      paid_only = false
      icon      = "/emojis/1f1fa-1f1f8.png"
    }
    "dfw" = {
      name      = "Dallas, Texas (US)"
      gateway   = true
      paid_only = false
      icon      = "/emojis/1f1fa-1f1f8.png"
    }
    "ewr" = {
      name      = "Secaucus, NJ (US)"
      gateway   = false
      paid_only = false
      icon      = "/emojis/1f1fa-1f1f8.png"
    }
    "eze" = {
      name      = "Ezeiza, Argentina"
      gateway   = false
      paid_only = false
      icon      = "/emojis/1f1e6-1f1f7.png"
    }
    "fra" = {
      name      = "Frankfurt, Germany"
      gateway   = true
      paid_only = true
      icon      = "/emojis/1f1e9-1f1ea.png"
    }
    "gdl" = {
      name      = "Guadalajara, Mexico"
      gateway   = false
      paid_only = false
      icon      = "/emojis/1f1f2-1f1fd.png"
    }
    "gig" = {
      name      = "Rio de Janeiro, Brazil"
      gateway   = false
      paid_only = false
      icon      = "/emojis/1f1e7-1f1f7.png"
    }
    "gru" = {
      name      = "Sao Paulo, Brazil"
      gateway   = false
      paid_only = false
      icon      = "/emojis/1f1e7-1f1f7.png"
    }
    "hkg" = {
      name      = "Hong Kong, Hong Kong"
      gateway   = true
      paid_only = false
      icon      = "/emojis/1f1ed-1f1f0.png"
    }
    "iad" = {
      name      = "Ashburn, Virginia (US)"
      gateway   = true
      paid_only = false
      icon      = "/emojis/1f1fa-1f1f8.png"
    }
    "jnb" = {
      name      = "Johannesburg, South Africa"
      gateway   = false
      paid_only = false
      icon      = "/emojis/1f1ff-1f1e6.png"
    }
    "lax" = {
      name      = "Los Angeles, California (US)"
      gateway   = true
      paid_only = false
      icon      = "/emojis/1f1fa-1f1f8.png"
    }
    "lhr" = {
      name      = "London, United Kingdom"
      gateway   = true
      paid_only = false
      icon      = "/emojis/1f1ec-1f1e7.png"
    }
    "mad" = {
      name      = "Madrid, Spain"
      gateway   = false
      paid_only = false
      icon      = "/emojis/1f1ea-1f1f8.png"
    }
    "mia" = {
      name      = "Miami, Florida (US)"
      gateway   = false
      paid_only = false
      icon      = "/emojis/1f1fa-1f1f8.png"
    }
    "nrt" = {
      name      = "Tokyo, Japan"
      gateway   = true
      paid_only = false
      icon      = "/emojis/1f1ef-1f1f5.png"
    }
    "ord" = {
      name      = "Chicago, Illinois (US)"
      gateway   = true
      paid_only = false
      icon      = "/emojis/1f1fa-1f1f8.png"
    }
    "otp" = {
      name      = "Bucharest, Romania"
      gateway   = false
      paid_only = false
      icon      = "/emojis/1f1f7-1f1f4.png"
    }
    "phx" = {
      name      = "Phoenix, Arizona (US)"
      gateway   = false
      paid_only = false
      icon      = "/emojis/1f1fa-1f1f8.png"
    }
    "qro" = {
      name      = "Querétaro, Mexico"
      gateway   = false
      paid_only = false
      icon      = "/emojis/1f1f2-1f1fd.png"
    }
    "scl" = {
      name      = "Santiago, Chile"
      gateway   = true
      paid_only = false
      icon      = "/emojis/1f1e8-1f1f1.png"
    }
    "sea" = {
      name      = "Seattle, Washington (US)"
      gateway   = true
      paid_only = false
      icon      = "/emojis/1f1fa-1f1f8.png"
    }
    "sin" = {
      name      = "Singapore, Singapore"
      gateway   = true
      paid_only = false
      icon      = "/emojis/1f1f8-1f1ec.png"
    }
    "sjc" = {
      name      = "San Jose, California (US)"
      gateway   = true
      paid_only = false
      icon      = "/emojis/1f1fa-1f1f8.png"
    }
    "syd" = {
      name      = "Sydney, Australia"
      gateway   = true
      paid_only = false
      icon      = "/emojis/1f1e6-1f1fa.png"
    }
    "waw" = {
      name      = "Warsaw, Poland"
      gateway   = false
      paid_only = false
      icon      = "/emojis/1f1f5-1f1f1.png"
    }
    "yul" = {
      name      = "Montreal, Canada"
      gateway   = false
      paid_only = false
      icon      = "/emojis/1f1e8-1f1e6.png"
    }
    "yyz" = {
      name      = "Toronto, Canada"
      gateway   = true
      paid_only = false
      icon      = "/emojis/1f1e8-1f1e6.png"
    }
  }
}

data "coder_parameter" "fly_region" {
  name         = "flyio_region"
  display_name = var.display_name
  description  = var.description
  default      = (var.default != null && var.default != "") && ((var.default != null ? contains(var.regions, var.default) : false) || length(var.regions) == 0) ? var.default : null
  mutable      = var.mutable
  dynamic "option" {
    for_each = { for k, v in local.regions : k => v if anytrue([for d in var.regions : k == d]) || length(var.regions) == 0 }
    content {
      name  = try(var.custom_names[option.key], option.value.name)
      icon  = try(var.custom_icons[option.key], option.value.icon)
      value = option.key
    }
  }
}

output "value" {
  value = data.coder_parameter.fly_region.value
}