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

The `default_availability_zone` output resolves the selected region to a
concrete zone (for example `us-east-1a`), so templates no longer have to guess
it by appending a letter to the region ID:

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
  availability_zone = module.aws_region.default_availability_zone
  # ...
}
```

### Use the outputs without a parameter

Set `create_parameter = false` to skip the region picker and pin a region
yourself, while still using the module's outputs (for example
`default_availability_zone` or the full `regions` catalog):

```tf
module "aws_region" {
  source           = "registry.coder.com/coder/aws-region/coder"
  version          = "1.1.0"
  create_parameter = false
  default          = "us-east-1"
}

provider "aws" {
  region = module.aws_region.value # "us-east-1"
}

# module.aws_region.default_availability_zone => "us-east-1a"
# module.aws_region.regions                   => full catalog keyed by region ID
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

| Output                      | Description                                                                          |
| --------------------------- | ------------------------------------------------------------------------------------ |
| `value`                     | The ID of the selected region, e.g. `us-east-1`.                                     |
| `default_availability_zone` | The default availability zone for the selected region, e.g. `us-east-1a`.            |
| `regions`                   | Every region keyed by ID, each with `name`, `icon`, and `default_availability_zone`. |

## Updating regions.json

`regions.json` is a generated catalog of region IDs, display names, and flag
icons, so the module needs no AWS provider or credentials at plan time.
Terraform only reads the file; all the flag logic lives in the script below.

Regenerate the whole file from AWS with the AWS CLI (any credentials) and `jq`,
run from this module's directory. Names and country codes come from the public
`global-infrastructure` SSM parameters in `us-east-1`:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Two-letter country code -> Coder flag emoji asset (regional indicator pair).
icon() {
  local a b
  a=$(printf '%x' $((0x1f1e6 + $(printf '%d' "'${1:0:1}") - 0x61)))
  b=$(printf '%x' $((0x1f1e6 + $(printf '%d' "'${1:1:1}") - 0x61)))
  printf '/emojis/%s-%s.png' "$a" "$b"
}

for region in $(aws ec2 describe-regions --all-regions \
  --query 'Regions[].RegionName' --output text | tr '\t' '\n' | sort); do
  name=$(aws ssm get-parameter --region us-east-1 \
    --name "/aws/service/global-infrastructure/regions/$region/longName" \
    --query Parameter.Value --output text)
  # European regions share the EU flag; every other region uses its country flag.
  if [[ $region == eu-* ]]; then
    country=eu
  else
    country=$(aws ssm get-parameter --region us-east-1 \
      --name "/aws/service/global-infrastructure/regions/$region/geolocationCountry" \
      --query Parameter.Value --output text | tr '[:upper:]' '[:lower:]')
  fi
  jq -n --arg value "$region" --arg name "$name" --arg icon "$(icon "$country")" \
    '{$value, $name, $icon}'
done | jq -s '.' > regions.json
```

## Related templates

For a complete AWS EC2 template, see the following examples in the [Coder Registry](https://registry.coder.com/).

- [AWS EC2 (Linux)](https://registry.coder.com/templates/aws-linux)
- [AWS EC2 (Windows)](https://registry.coder.com/templates/aws-windows)
