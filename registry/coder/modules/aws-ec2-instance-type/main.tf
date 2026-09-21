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
  description = "The default instance type to preselect. Must be part of the selected type_category, e.g. \"t3.micro\"."
  type        = string
  default     = ""
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
  # Static catalog (see instance-types.json) so the module needs no AWS provider
  # or credentials at plan time, matching the aws-region module's approach.
  instance_types = jsondecode(file("${path.module}/instance-types.json"))
}

data "coder_parameter" "instance_type" {
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
  value       = data.coder_parameter.instance_type.value
}

output "instances" {
  description = "All AWS EC2 instance types keyed by instance type ID, with raw specs (vcpus, memory_mib, gpus) and architecture (coder_arch, ami)."
  value       = { for instance in local.instance_types : instance.value => instance }
}
