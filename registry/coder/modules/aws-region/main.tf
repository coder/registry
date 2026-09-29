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
  default     = null
  description = "The default region to preselect, e.g. \"us-east-1\". Leave unset for no preselection; also used as the selected region when create_parameter is false."
  type        = string

  validation {
    condition     = var.default == null || can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", var.default))
    error_message = "default must be null or a valid AWS region ID, e.g. \"us-east-1\"."
  }
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

  validation {
    condition     = alltrue([for region in var.exclude : can(regex("^[a-z]{2}-[a-z]+-[0-9]+$", region))])
    error_message = "exclude must contain valid AWS region IDs, e.g. \"ap-northeast-2\"."
  }
}

variable "coder_parameter_order" {
  type        = number
  description = "The order determines the position of a template parameter in the UI/CLI presentation. The lowest order is shown first and parameters with equal order are sorted by name (ascending order)."
  default     = null
}

variable "create_parameter" {
  type        = bool
  description = "Whether to create the coder_parameter. Set to false to skip the region picker and use the module only for its outputs, e.g. the regions catalog or a default_availability_zone for a fixed default region."
  default     = true
}

locals {
  # Read regions.json with a fallback: Terraform resolves file() from the root
  # module, but Coder's dynamic parameters preview resolves it from this module's
  # directory, so neither path works on its own.
  regions = jsondecode(try(file("${path.module}/regions.json"), file("regions.json")))

  regions_by_id = {
    for region in local.regions : region.value => {
      value                     = region.value
      name                      = region.name
      icon                      = region.icon
      default_availability_zone = "${region.value}a"
    }
  }

  selected_region = var.create_parameter ? one(data.coder_parameter.region[*].value) : var.default
}

data "coder_parameter" "region" {
  count        = var.create_parameter ? 1 : 0
  name         = "aws_region"
  display_name = var.display_name
  description  = var.description
  default      = var.default
  order        = var.coder_parameter_order
  mutable      = var.mutable
  dynamic "option" {
    for_each = [for region in local.regions : region if !contains(var.exclude, region.value)]
    content {
      name  = try(var.custom_names[option.value.value], option.value.name)
      icon  = try(var.custom_icons[option.value.value], option.value.icon)
      value = option.value.value
    }
  }
}

output "value" {
  description = "The ID of the selected AWS region, e.g. \"us-east-1\". Falls back to var.default when create_parameter is false."
  value       = local.selected_region
}

output "default_availability_zone" {
  description = "The default availability zone for the selected region, e.g. \"us-east-1a\". Empty when no region is selected."
  value       = try(local.regions_by_id[local.selected_region].default_availability_zone, "")
}

output "regions" {
  description = "All AWS regions keyed by region ID, each with name, icon, and default_availability_zone."
  value       = local.regions_by_id
}
