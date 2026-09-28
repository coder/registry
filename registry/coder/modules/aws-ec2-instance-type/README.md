---
display_name: AWS EC2 Instance Type
description: A parameter with human readable AWS EC2 instance type names
icon: ../../../../.icons/aws.svg
verified: false
tags: [helper, parameter, instances, aws]
---

# AWS EC2 Instance Type

A parameter with common AWS EC2 instance types, filtered by instance family.
Each option is labeled with its vCPU, RAM, and architecture so developers can
select the machine that best fits their workspace.

```tf
module "aws_ec2_instance_type" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/aws-ec2-instance-type/coder"
  version = "1.0.0"
  default = "t3.micro"
}

resource "aws_instance" "dev" {
  instance_type = module.aws_ec2_instance_type[0].value
  # ...
}
```

## Examples

### Choose instance families

By default only the `t3` family is offered. Pass `include` to expose more
families and preselect one:

```tf
module "aws_ec2_instance_type" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/aws-ec2-instance-type/coder"
  version = "1.0.0"
  include = ["t3", "m5", "c5"]
  default = "m5.large"
}
```

The bundled catalog covers the `t3`, `t4g`, `m5`, `m7g`, `c5`, `r5`, `i3`, and
`g4dn` families.

### Customize labels and tooltips

Each option is labeled with its specs and architecture (for example
`2 vCPU, 4 GiB RAM (amd64)`) and shows the instance type as a tooltip. Override
either per instance type:

```tf
module "aws_ec2_instance_type" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/aws-ec2-instance-type/coder"
  version = "1.0.0"
  default = "t3.medium"

  custom_metadata = {
    "t3.medium" = {
      name        = "Standard workspace"
      description = "Recommended default"
    }
  }
}
```

### Architecture-aware provisioning

The `instances` output maps every instance type ID to its metadata, including architecture fields. Look up the selected value to configure the agent and pick a matching AMI:

```tf
module "aws_ec2_instance_type" {
  source  = "registry.coder.com/coder/aws-ec2-instance-type/coder"
  version = "1.0.0"
}

locals {
  selected = module.aws_ec2_instance_type.instances[module.aws_ec2_instance_type.value]
}

resource "coder_agent" "dev" {
  arch = local.selected.coder_arch # amd64 or arm64
  os   = "linux"
}

data "aws_ami" "workspace" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "architecture"
    values = [local.selected.arch] # x86_64 or arm64
  }
}
```

### Use the catalog without a parameter

Set `create_parameter = false` to skip the picker (for example when the template pins the size) while still using the `instances` catalog:

```tf
module "aws_ec2_instance_type" {
  source           = "registry.coder.com/coder/aws-ec2-instance-type/coder"
  version          = "1.0.0"
  create_parameter = false
  default          = "t4g.large"
}
```

## Related templates

For a complete AWS EC2 template, see the following examples in the [Coder Registry](https://registry.coder.com/).

- [AWS EC2 (Linux)](https://registry.coder.com/templates/aws-linux)
- [AWS EC2 (Windows)](https://registry.coder.com/templates/aws-windows)
