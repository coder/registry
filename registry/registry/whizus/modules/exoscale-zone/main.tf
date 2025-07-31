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
  default     = "Exoscale Region"
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
  # This is a static list because the zones don't change _that_
  # frequently and including the `exoscale_zones` data source requires
  # the provider, which requires a zone.
  # https://www.exoscale.com/datacenters/
  zones = {
    "de-fra-1" = {
      name = "Frankfurt - Germany"
      icon = "/emojis/1f1e9-1f1ea.png"
    }
    "at-vie-1" = {
      name = "Vienna 1 - Austria"
      icon = "/emojis/1f1e6-1f1f9.png"
    }
    "at-vie-2" = {
      name = "Vienna 2 - Austria"
      icon = "/emojis/1f1e6-1f1f9.png"
    }
    "ch-gva-2" = {
      name = "Geneva - Switzerland"
      icon = "/emojis/1f1e8-1f1ed.png"
    }
    "ch-dk-2" = {
      name = "Zurich - Switzerland"
      icon = "/emojis/1f1e8-1f1ed.png"
    }
    "bg-sof-1" = {
      name = "Sofia - Bulgaria"
      icon = "/emojis/1f1e7-1f1ec.png"
    }
    "de-muc-1" = {
      name = "Munich - Germany"
      icon = "/emojis/1f1e9-1f1ea.png"
    }
  }
}

data "coder_parameter" "zone" {
  name         = "exoscale_zone"
  display_name = var.display_name
  description  = var.description
  default      = var.default == "" ? null : var.default
  order        = var.coder_parameter_order
  mutable      = var.mutable
  dynamic "option" {
    for_each = { for k, v in local.zones : k => v if !(contains(var.exclude, k)) }
    content {
      name  = try(var.custom_names[option.key], option.value.name)
      icon  = try(var.custom_icons[option.key], option.value.icon)
      value = option.key
    }
  }
}

output "value" {
  value = data.coder_parameter.zone.value
}