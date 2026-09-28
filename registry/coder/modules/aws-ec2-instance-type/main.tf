terraform {
  required_version = ">= 1.3"

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
  description = "The default instance type to preselect (must belong to an included family), or the fixed value returned when create_parameter is false."
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

variable "custom_metadata" {
  description = "Per instance type overrides keyed by instance type ID. name replaces the generated \"vCPU / RAM / arch\" label; description replaces the instance-type tooltip."
  type = map(object({
    name        = optional(string)
    description = optional(string)
  }))
  default = {}
}

variable "include" {
  description = "Instance families to offer in the picker, e.g. [\"t3\", \"m5\", \"c5\"]. Defaults to t3."
  type        = list(string)
  default     = ["t3"]
}

variable "coder_parameter_order" {
  description = "The order determines the position of a template parameter in the UI/CLI presentation. The lowest order is shown first and parameters with equal order are sorted by name (ascending order)."
  type        = number
  default     = null
}

locals {
  # Specs come straight from `aws ec2 describe-instance-types` (regenerate with
  # .scripts/update.sh). coder_arch is derived from arch here because AWS spells
  # it x86_64/arm64 while Coder uses amd64/arm64.
  #
  # Read instance-types.json with a fallback: Terraform resolves file() from the
  # root module, but Coder's dynamic parameters preview resolves it from this
  # module's directory, so neither path works on its own.
  raw_instances = jsondecode(try(file("${path.module}/instance-types.json"), file("instance-types.json")))

  instance_types = [
    for instance in local.raw_instances : merge(instance, {
      coder_arch = instance.arch == "arm64" ? "arm64" : "amd64"
    })
  ]

  included_instances = [
    for instance in local.instance_types : instance
    if contains(var.include, split(".", instance.type)[0])
  ]

  spec_labels = {
    for instance in local.included_instances : instance.type => format(
      "%d vCPU, %g GiB RAM%s (%s)",
      instance.vcpus,
      instance.memory_mib / 1024,
      instance.gpus > 0 ? format(", %d GPU", instance.gpus) : "",
      instance.coder_arch
    )
  }

  label_counts = {
    for label in distinct(values(local.spec_labels)) : label =>
    length([for l in values(local.spec_labels) : l if l == label])
  }

  # spec label, with the instance type appended when families share a label so
  # option names stay unique (Coder requires that).
  display_labels = {
    for instance_type, spec_label in local.spec_labels : instance_type =>
    local.label_counts[spec_label] > 1 ? "${trimsuffix(spec_label, ")")}, ${instance_type})" : spec_label
  }

  # Final picker entries in the catalog's memory-sorted order. name is the spec
  # label unless custom_metadata overrides it; description is the instance type,
  # shown as the option's tooltip.
  options = [
    for instance in local.included_instances : {
      instance_type = instance.type
      name          = coalesce(try(var.custom_metadata[instance.type].name, null), local.display_labels[instance.type])
      description   = coalesce(try(var.custom_metadata[instance.type].description, null), instance.type)
    }
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
    # local.options maps each instance type to its picker name and description.
    for_each = local.options
    iterator = opt
    content {
      value       = opt.value.instance_type
      name        = opt.value.name
      description = opt.value.description
    }
  }
}

output "value" {
  description = "The selected AWS EC2 instance type. Use it as the key into the instances output."
  value       = var.create_parameter ? one(data.coder_parameter.instance_type[*].value) : var.default
}

output "instances" {
  description = "All AWS EC2 instance types keyed by instance type ID, with raw specs (vcpus, memory_mib, gpus) and architecture (coder_arch, arch)."
  value       = { for instance in local.instance_types : instance.type => instance }
}
