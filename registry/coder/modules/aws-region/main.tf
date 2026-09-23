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
  # Flag emoji per two-letter flag code. Defined here so the icon paths live in
  # one place; "eu" is the shared European flag.
  flag_emojis = {
    au = "/emojis/1f1e6-1f1fa.png"
    bh = "/emojis/1f1e7-1f1ed.png"
    br = "/emojis/1f1e7-1f1f7.png"
    ca = "/emojis/1f1e8-1f1e6.png"
    eu = "/emojis/1f1ea-1f1fa.png"
    hk = "/emojis/1f1ed-1f1f0.png"
    id = "/emojis/1f1ee-1f1e9.png"
    il = "/emojis/1f1ee-1f1f1.png"
    in = "/emojis/1f1ee-1f1f3.png"
    jp = "/emojis/1f1ef-1f1f5.png"
    kr = "/emojis/1f1f0-1f1f7.png"
    sg = "/emojis/1f1f8-1f1ec.png"
    us = "/emojis/1f1fa-1f1f8.png"
    za = "/emojis/1f1ff-1f1e6.png"
  }

  # Flag per region, derived from the region ID so regions.json only needs the
  # region ID and display name. A region defaults to its geographic prefix's
  # flag (every us-* region uses "us", every eu-* region shares "eu", and so on);
  # the Asia Pacific and Middle East prefixes span several countries, so those
  # regions are mapped individually.
  prefix_flags = {
    af = "za"
    ca = "ca"
    eu = "eu"
    il = "il"
    sa = "br"
    us = "us"
  }
  region_flags = {
    "ap-east-1"      = "hk"
    "ap-northeast-1" = "jp"
    "ap-northeast-2" = "kr"
    "ap-northeast-3" = "jp"
    "ap-south-1"     = "in"
    "ap-south-2"     = "in"
    "ap-southeast-1" = "sg"
    "ap-southeast-2" = "au"
    "ap-southeast-3" = "id"
    "ap-southeast-4" = "au"
    "me-south-1"     = "bh"
  }

  # Region catalog (see regions.json). Kept as static data so the module needs
  # no AWS provider or credentials at plan time.
  #
  # The try() reads regions.json under both Terraform and Coder's dynamic
  # parameters preview: Terraform resolves file() relative to the root module
  # (so path.module is required), while the preview evaluator resolves it
  # relative to this module's own directory (so path.module points one level too
  # deep). Without the fallback the parameter renders with no options under
  # dynamic parameters.
  regions = jsondecode(try(file("${path.module}/regions.json"), file("regions.json")))

  # Resolve each region's flag code once: an explicit entry wins, otherwise the
  # geographic prefix supplies it.
  region_flag = {
    for region in local.regions : region.value =>
    try(local.region_flags[region.value], local.prefix_flags[split("-", region.value)[0]])
  }

  regions_by_id = {
    for region in local.regions : region.value => {
      value                     = region.value
      name                      = region.name
      flag                      = local.region_flag[region.value]
      icon                      = local.flag_emojis[local.region_flag[region.value]]
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
      icon  = try(var.custom_icons[option.value.value], local.flag_emojis[local.region_flag[option.value.value]])
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
  description = "All AWS regions keyed by region ID, each with name, flag, icon, and default_availability_zone."
  value       = local.regions_by_id
}
