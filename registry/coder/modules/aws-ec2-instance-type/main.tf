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

variable "custom_names" {
  description = "A map of custom labels for instance type IDs, overriding the generated \"vCPU / RAM / arch\" label."
  type        = map(string)
  default     = {}
}

variable "custom_descriptions" {
  description = "A map of custom tooltips for instance type IDs, overriding the default instance type tooltip."
  type        = map(string)
  default     = {}
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
  # .scripts/update.sh). category and coder_arch are derived here because AWS
  # neither groups instances nor uses Coder's arch spelling.
  #
  # Read instance-types.json with a fallback: Terraform resolves file() from the
  # root module, but Coder's dynamic parameters preview resolves it from this
  # module's directory, so neither path works on its own.
  raw_instances = jsondecode(try(file("${path.module}/instance-types.json"), file("instance-types.json")))

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

  included_instances = [
    for instance in local.instance_types : instance
    if contains(var.include, split(".", instance.value)[0])
  ]

  spec_labels = {
    for instance in local.included_instances : instance.value => format(
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

  # Coder requires unique option names, but instance families share specs, so a
  # label used by more than one included instance gets the instance type added
  # inside the parentheses, e.g. "2 vCPU, 4 GiB RAM (amd64, c5.large)".
  option_names = {
    for value, label in local.spec_labels : value =>
    local.label_counts[label] > 1 ? "${trimsuffix(label, ")")}, ${value})" : label
  }
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
    for_each = local.included_instances
    content {
      # Label with specs and architecture; the instance type is the tooltip.
      name        = try(var.custom_names[option.value.value], local.option_names[option.value.value])
      description = try(var.custom_descriptions[option.value.value], option.value.value)
      value       = option.value.value
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
