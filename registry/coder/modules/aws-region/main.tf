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
  # Static catalog (see regions.json) so the module needs no AWS provider or
  # credentials at plan time. The regions don't change frequently, and the
  # aws_regions data source would require a provider, which requires a region.
  regions       = jsondecode(file("${path.module}/regions.json"))
  regions_by_id = { for region in local.regions : region.value => region }
}

data "coder_parameter" "region" {
  name         = "aws_region"
  display_name = var.display_name
  description  = var.description
  default      = var.default == "" ? null : var.default
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
  description = "The ID of the selected AWS region, e.g. \"us-east-1\"."
  value       = data.coder_parameter.region.value
}

output "availability_zone" {
  description = "The default availability zone for the selected region, e.g. \"us-east-1a\". Empty when no region is selected."
  value       = try(local.regions_by_id[data.coder_parameter.region.value].availability_zone, "")
}

output "regions" {
  description = "All AWS regions keyed by region ID, each with name, icon, and availability_zone."
  value       = local.regions_by_id
}
