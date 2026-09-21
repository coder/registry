---
display_name: AWS EC2 Instance Type
description: A parameter with human readable AWS EC2 instance type names
icon: ../../../../.icons/aws.svg
verified: false
tags: [helper, parameter, instances, aws]
---

# AWS EC2 Instance Type

A parameter with common AWS EC2 instance types, grouped by category. This allows
developers to select the machine that best fits their workspace.

```tf
module "aws_ec2_instance_type" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/aws-ec2-instance-type/coder"
  version = "1.0.0"
  default = "t3.micro"
}

resource "aws_instance" "dev" {
  instance_type = module.aws_ec2_instance_type.value
  # ...
}
```

## Examples

### Restrict to a category

Only expose compute optimized instances and preselect one:

```tf
module "aws_ec2_instance_type" {
  count         = data.coder_workspace.me.start_count
  source        = "registry.coder.com/coder/aws-ec2-instance-type/coder"
  version       = "1.0.0"
  default       = "c5.2xlarge"
  type_category = ["compute"]
}
```

The available categories are `general`, `compute`, `memory`, `storage`, and `gpu`.

### Customize names and descriptions

Override the display name and description for specific instance types:

```tf
module "aws_ec2_instance_type" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/aws-ec2-instance-type/coder"
  version = "1.0.0"
  default = "t3.medium"

  custom_names = {
    "t3.medium" : "Standard workspace"
  }

  custom_descriptions = {
    "t3.medium" : "2 vCPU, 4 GiB RAM (recommended)"
  }
}
```

### Exclude instance types

Hide the smallest burstable types:

```tf
module "aws_ec2_instance_type" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/aws-ec2-instance-type/coder"
  version = "1.0.0"
  exclude = ["t3.nano", "t3.micro"]
}
```

## Related templates

For a complete AWS EC2 template, see the following examples in the [Coder Registry](https://registry.coder.com/).

- [AWS EC2 (Linux)](https://registry.coder.com/templates/aws-linux)
- [AWS EC2 (Windows)](https://registry.coder.com/templates/aws-windows)
