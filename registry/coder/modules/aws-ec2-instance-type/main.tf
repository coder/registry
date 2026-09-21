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
  # https://aws.amazon.com/ec2/instance-types/
  general_instances = [
    {
      value       = "t3.nano"
      name        = "t3.nano"
      description = "2 vCPU, 0.5 GiB RAM"
    },
    {
      value       = "t3.micro"
      name        = "t3.micro"
      description = "2 vCPU, 1 GiB RAM"
    },
    {
      value       = "t3.small"
      name        = "t3.small"
      description = "2 vCPU, 2 GiB RAM"
    },
    {
      value       = "t3.medium"
      name        = "t3.medium"
      description = "2 vCPU, 4 GiB RAM"
    },
    {
      value       = "t3.large"
      name        = "t3.large"
      description = "2 vCPU, 8 GiB RAM"
    },
    {
      value       = "t3.xlarge"
      name        = "t3.xlarge"
      description = "4 vCPU, 16 GiB RAM"
    },
    {
      value       = "t3.2xlarge"
      name        = "t3.2xlarge"
      description = "8 vCPU, 32 GiB RAM"
    },
    {
      value       = "m5.large"
      name        = "m5.large"
      description = "2 vCPU, 8 GiB RAM"
    },
    {
      value       = "m5.xlarge"
      name        = "m5.xlarge"
      description = "4 vCPU, 16 GiB RAM"
    },
    {
      value       = "m5.2xlarge"
      name        = "m5.2xlarge"
      description = "8 vCPU, 32 GiB RAM"
    },
    {
      value       = "m5.4xlarge"
      name        = "m5.4xlarge"
      description = "16 vCPU, 64 GiB RAM"
    },
    {
      value       = "m5.8xlarge"
      name        = "m5.8xlarge"
      description = "32 vCPU, 128 GiB RAM"
    },
    {
      value       = "m5.12xlarge"
      name        = "m5.12xlarge"
      description = "48 vCPU, 192 GiB RAM"
    },
    {
      value       = "m5.16xlarge"
      name        = "m5.16xlarge"
      description = "64 vCPU, 256 GiB RAM"
    },
    {
      value       = "m5.24xlarge"
      name        = "m5.24xlarge"
      description = "96 vCPU, 384 GiB RAM"
    }
  ]
  compute_instances = [
    {
      value       = "c5.large"
      name        = "c5.large"
      description = "2 vCPU, 4 GiB RAM"
    },
    {
      value       = "c5.xlarge"
      name        = "c5.xlarge"
      description = "4 vCPU, 8 GiB RAM"
    },
    {
      value       = "c5.2xlarge"
      name        = "c5.2xlarge"
      description = "8 vCPU, 16 GiB RAM"
    },
    {
      value       = "c5.4xlarge"
      name        = "c5.4xlarge"
      description = "16 vCPU, 32 GiB RAM"
    },
    {
      value       = "c5.9xlarge"
      name        = "c5.9xlarge"
      description = "36 vCPU, 72 GiB RAM"
    },
    {
      value       = "c5.12xlarge"
      name        = "c5.12xlarge"
      description = "48 vCPU, 96 GiB RAM"
    },
    {
      value       = "c5.18xlarge"
      name        = "c5.18xlarge"
      description = "72 vCPU, 144 GiB RAM"
    },
    {
      value       = "c5.24xlarge"
      name        = "c5.24xlarge"
      description = "96 vCPU, 192 GiB RAM"
    }
  ]
  memory_instances = [
    {
      value       = "r5.large"
      name        = "r5.large"
      description = "2 vCPU, 16 GiB RAM"
    },
    {
      value       = "r5.xlarge"
      name        = "r5.xlarge"
      description = "4 vCPU, 32 GiB RAM"
    },
    {
      value       = "r5.2xlarge"
      name        = "r5.2xlarge"
      description = "8 vCPU, 64 GiB RAM"
    },
    {
      value       = "r5.4xlarge"
      name        = "r5.4xlarge"
      description = "16 vCPU, 128 GiB RAM"
    },
    {
      value       = "r5.8xlarge"
      name        = "r5.8xlarge"
      description = "32 vCPU, 256 GiB RAM"
    },
    {
      value       = "r5.12xlarge"
      name        = "r5.12xlarge"
      description = "48 vCPU, 384 GiB RAM"
    },
    {
      value       = "r5.16xlarge"
      name        = "r5.16xlarge"
      description = "64 vCPU, 512 GiB RAM"
    },
    {
      value       = "r5.24xlarge"
      name        = "r5.24xlarge"
      description = "96 vCPU, 768 GiB RAM"
    }
  ]
  storage_instances = [
    {
      value       = "i3.large"
      name        = "i3.large"
      description = "2 vCPU, 15.25 GiB RAM"
    },
    {
      value       = "i3.xlarge"
      name        = "i3.xlarge"
      description = "4 vCPU, 30.5 GiB RAM"
    },
    {
      value       = "i3.2xlarge"
      name        = "i3.2xlarge"
      description = "8 vCPU, 61 GiB RAM"
    },
    {
      value       = "i3.4xlarge"
      name        = "i3.4xlarge"
      description = "16 vCPU, 122 GiB RAM"
    },
    {
      value       = "i3.8xlarge"
      name        = "i3.8xlarge"
      description = "32 vCPU, 244 GiB RAM"
    },
    {
      value       = "i3.16xlarge"
      name        = "i3.16xlarge"
      description = "64 vCPU, 488 GiB RAM"
    }
  ]
  gpu_instances = [
    {
      value       = "g4dn.xlarge"
      name        = "g4dn.xlarge"
      description = "4 vCPU, 16 GiB RAM, 1 GPU"
    },
    {
      value       = "g4dn.2xlarge"
      name        = "g4dn.2xlarge"
      description = "8 vCPU, 32 GiB RAM, 1 GPU"
    },
    {
      value       = "g4dn.4xlarge"
      name        = "g4dn.4xlarge"
      description = "16 vCPU, 64 GiB RAM, 1 GPU"
    },
    {
      value       = "g4dn.8xlarge"
      name        = "g4dn.8xlarge"
      description = "32 vCPU, 128 GiB RAM, 1 GPU"
    },
    {
      value       = "g4dn.12xlarge"
      name        = "g4dn.12xlarge"
      description = "48 vCPU, 192 GiB RAM, 4 GPU"
    },
    {
      value       = "g4dn.16xlarge"
      name        = "g4dn.16xlarge"
      description = "64 vCPU, 256 GiB RAM, 1 GPU"
    }
  ]
}

data "coder_parameter" "instance_type" {
  name         = "aws_ec2_instance_type"
  display_name = var.display_name
  description  = var.description
  default      = var.default == "" ? null : var.default
  order        = var.coder_parameter_order
  mutable      = var.mutable
  dynamic "option" {
    for_each = [for instance in concat(
      contains(var.type_category, "general") ? local.general_instances : [],
      contains(var.type_category, "compute") ? local.compute_instances : [],
      contains(var.type_category, "memory") ? local.memory_instances : [],
      contains(var.type_category, "storage") ? local.storage_instances : [],
      contains(var.type_category, "gpu") ? local.gpu_instances : []
    ) : instance if !(contains(var.exclude, instance.value))]
    content {
      name        = try(var.custom_names[option.value.value], option.value.name)
      description = try(var.custom_descriptions[option.value.value], option.value.description)
      value       = option.value.value
    }
  }
}

output "value" {
  description = "The selected AWS EC2 instance type."
  value       = data.coder_parameter.instance_type.value
}
