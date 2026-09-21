---
display_name: AWS Region
description: A parameter with human region names and icons
icon: ../../../../.icons/aws.svg
verified: true
tags: [helper, parameter, regions, aws]
---

# AWS Region

A parameter with all AWS regions. This allows developers to select
the region closest to them.

Customize the preselected parameter value:

```tf
module "aws_region" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/aws-region/coder"
  version = "1.1.0"
  default = "us-east-1"
}

provider "aws" {
  region = module.aws_region[0].value
}
```

![AWS Regions](../../.images/aws-regions.png)

## Examples

### Provision in the selected region's availability zone

The `availability_zone` output resolves the selected region to a concrete zone
(for example `us-east-1a`), so templates no longer have to guess it by appending
a letter to the region ID:

```tf
module "aws_region" {
  source  = "registry.coder.com/coder/aws-region/coder"
  version = "1.1.0"
  default = "us-east-1"
}

provider "aws" {
  region = module.aws_region.value
}

resource "aws_instance" "dev" {
  ami               = data.aws_ami.ubuntu.id
  instance_type     = "t3.micro"
  availability_zone = module.aws_region.availability_zone
  # ...
}
```

### Customize regions

Change the display name and icon for a region using the corresponding maps:

```tf
module "aws_region" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/aws-region/coder"
  version = "1.1.0"
  default = "ap-south-1"

  custom_names = {
    "ap-south-1" : "Awesome Mumbai!"
  }

  custom_icons = {
    "ap-south-1" : "/emojis/1f33a.png"
  }
}

provider "aws" {
  region = module.aws_region[0].value
}
```

![AWS Custom](../../.images/aws-custom.png)

### Exclude regions

Hide the Asia Pacific regions Seoul and Osaka:

```tf
module "aws_region" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/aws-region/coder"
  version = "1.1.0"
  exclude = ["ap-northeast-2", "ap-northeast-3"]
}

provider "aws" {
  region = module.aws_region[0].value
}
```

![AWS Exclude](../../.images/aws-exclude.png)

## Outputs

| Output              | Description                                                                                                   |
| ------------------- | ------------------------------------------------------------------------------------------------------------- |
| `value`             | The ID of the selected region, e.g. `us-east-1`.                                                              |
| `availability_zone` | The default availability zone for the selected region, e.g. `us-east-1a`.                                     |
| `regions`           | Every region keyed by ID, each with its `name`, `icon`, and `availability_zone`. Sourced from `regions.json`. |

## Related templates

For a complete AWS EC2 template, see the following examples in the [Coder Registry](https://registry.coder.com/).

- [AWS EC2 (Linux)](https://registry.coder.com/templates/aws-linux)
- [AWS EC2 (Windows)](https://registry.coder.com/templates/aws-windows)
