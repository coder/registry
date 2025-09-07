terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.11"
    }
  }
}

variable "display_name" {
  default     = "DigitalOcean Region"
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
  description = "Default region"
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

variable "single_zone_per_region" {
  default     = true
  description = "Whether to only include a single zone per region."
  type        = bool
}

variable "coder_parameter_order" {
  type        = number
  description = "The order determines the position of a template parameter in the UI/CLI presentation. The lowest order is shown first and parameters with equal order are sorted by name (ascending order)."
  default     = null
}

data "coder_parameter" "gpu_only" {
  name         = "digitalocean_gpu_only"
  display_name = "GPU-only regions"
  description  = "Show only regions with GPUs"
  type         = "bool"
  form_type    = "checkbox"
  default      = false
  mutable      = var.mutable
  order        = var.coder_parameter_order
}

locals {
  zones = {
    # Active datacenters (recommended for new workloads)
    "nyc1" = {
      gpu  = false
      name = "New York City, USA (NYC1)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "nyc3" = {
      gpu  = false
      name = "New York City, USA (NYC3)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "ams3" = {
      gpu  = false
      name = "Amsterdam, Netherlands"
      icon = "/emojis/1f1f3-1f1f1.png"
    }
    "sfo3" = {
      gpu  = false
      name = "San Francisco, USA"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "sgp1" = {
      gpu  = false
      name = "Singapore"
      icon = "/emojis/1f1f8-1f1ec.png"
    }
    "lon1" = {
      gpu  = false
      name = "London, United Kingdom"
      icon = "/emojis/1f1ec-1f1e7.png"
    }
    "fra1" = {
      gpu  = false
      name = "Frankfurt, Germany"
      icon = "/emojis/1f1e9-1f1ea.png"
    }
    "tor1" = {
      gpu  = true
      name = "Toronto, Canada"
      icon = "/emojis/1f1e8-1f1e6.png"
    }
    "blr1" = {
      gpu  = false
      name = "Bangalore, India"
      icon = "/emojis/1f1ee-1f1f3.png"
    }
    "syd1" = {
      gpu  = false
      name = "Sydney, Australia"
      icon = "/emojis/1f1e6-1f1fa.png"
    }
    "atl1" = {
      gpu  = false
      name = "Atlanta, USA"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    # Legacy/Restricted datacenters (not recommended for new workloads)
    "nyc2" = {
      gpu  = true # GPU available but restricted to existing users
      name = "New York City, USA (Legacy)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "sfo2" = {
      gpu  = false # No GPU available per current regional availability
      name = "San Francisco, USA (Legacy SFO2)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "sfo1" = {
      gpu  = false # No GPU in legacy datacenter
      name = "San Francisco, USA (Legacy SFO1)"
      icon = "/emojis/1f1fa-1f1f8.png"
    }
    "ams2" = {
      gpu  = false # No GPU in legacy datacenter
      name = "Amsterdam, Netherlands (Legacy)"
      icon = "/emojis/1f1f3-1f1f1.png"
    }
  }
}

locals {
  allowed_regions = data.coder_parameter.gpu_only.value ? [for k, v in local.zones : k if v.gpu] : keys(local.zones)
  default_region  = data.coder_parameter.gpu_only.value ? (length([for k, v in local.zones : k if v.gpu]) > 0 ? [for k, v in local.zones : k if v.gpu][0] : null) : (var.default != null && var.default != "" ? var.default : keys(local.zones)[0])
}

data "coder_parameter" "region" {
  name         = "digitalocean_region"
  display_name = var.display_name
  description  = var.description
  icon         = "/icon/digital-ocean.svg"
  mutable      = var.mutable
  form_type    = "radio"
  default      = local.default_region
  order        = var.coder_parameter_order
  dynamic "option" {
    for_each = {
      for k, v in local.zones : k => v
      if contains(local.allowed_regions, k)
    }
    content {
      icon        = try(var.custom_icons[option.key], option.value.icon)
      name        = try(var.custom_names[option.key], option.value.name)
      description = option.key
      value       = option.key
    }
  }


}
output "value" {
  description = "DigitalOcean region identifier."
  value       = data.coder_parameter.region.value
}
