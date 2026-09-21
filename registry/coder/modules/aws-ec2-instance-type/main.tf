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
  description = "The display name of the parameter."
  type        = string
  default     = "AWS EC2 Instance Type"
}

variable "description" {
  description = "The description of the parameter."
  type        = string
  default     = "Select the EC2 instance type to use for the workspace. See https://aws.amazon.com/ec2/instance-types/ for details."
}

variable "default" {
  description = "The default instance type to preselect (must be part of type_category), or the fixed value returned when create_parameter is false."
  type        = string
  default     = ""
}

variable "create_parameter" {
  description = "Whether to create the built-in coder_parameter. Set to false to skip the picker and return default while still exposing the instances catalog."
  type        = bool
  default     = true
}

variable "mutable" {
  description = "Whether the parameter can be changed after creation."
  type        = bool
  default     = false
}

variable "custom_names" {
  description = "A map of custom display names for instance type IDs."
  type        = map(string)
  default     = {}
}

variable "custom_descriptions" {
  description = "A map of custom descriptions for instance type IDs."
  type        = map(string)
  default     = {}
}

variable "type_category" {
  description = "A list of instance type categories the user is allowed to choose. One of [\"general\", \"compute\", \"memory\", \"storage\", \"gpu\"]."
  type        = list(string)
  default     = ["general"]
}

variable "exclude" {
  description = "A list of instance type IDs to exclude, e.g. [\"t3.nano\", \"m5.24xlarge\"]."
  type        = list(string)
  default     = []
}

variable "coder_parameter_order" {
  description = "The order determines the position of a template parameter in the UI/CLI presentation. The lowest order is shown first and parameters with equal order are sorted by name (ascending order)."
  type        = number
  default     = null
}

locals {
  # Specs come straight from `aws ec2 describe-instance-types` (see the PR/README
  # for the regeneration command). category and coder_arch are derived here
  # because AWS neither groups instances nor uses Coder's arch spelling.
  raw_instances = jsondecode(file("${path.module}/instance-types.json"))

  family_category = {
    t3   = "general"
    m5   = "general"
    t4g  = "general"
    m7g  = "general"
    c5   = "compute"
    r5   = "memory"
    i3   = "storage"
    g4dn = "gpu"
  }

  instance_types = [
    for instance in local.raw_instances : merge(instance, {
      category   = local.family_category[split(".", instance.value)[0]]
      coder_arch = instance.ami == "arm64" ? "arm64" : "amd64"
    })
  ]
}

data "coder_parameter" "instance_type" {
  count        = var.create_parameter ? 1 : 0
  name         = "aws_ec2_instance_type"
  display_name = var.display_name
  description  = var.description
  default      = var.default == "" ? null : var.default
  order        = var.coder_parameter_order
  mutable      = var.mutable
  dynamic "option" {
    for_each = [
      for instance in local.instance_types : instance
      if contains(var.type_category, instance.category) && !contains(var.exclude, instance.value)
    ]
    content {
      name = try(var.custom_names[option.value.value], option.value.value)
      description = try(
        var.custom_descriptions[option.value.value],
        format(
          "%d vCPU, %g GiB RAM%s",
          option.value.vcpus,
          option.value.memory_mib / 1024,
          option.value.gpus > 0 ? format(", %d GPU", option.value.gpus) : ""
        )
      )
      value = option.value.value
    }
  }
}

output "value" {
  description = "The selected AWS EC2 instance type. Use it as the key into the instances output."
  value       = var.create_parameter ? one(data.coder_parameter.instance_type[*].value) : var.default
}

output "instances" {
  description = "All AWS EC2 instance types keyed by instance type ID, with raw specs (vcpus, memory_mib, gpus) and architecture (coder_arch, ami)."
  value       = { for instance in local.instance_types : instance.value => instance }
}
