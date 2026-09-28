terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# See https://registry.coder.com/modules/coder/aws-region
module "aws_region" {
  source  = "registry.coder.com/coder/aws-region/coder"
  version = "~> 1.1"
  default = "us-east-1"
}

# See https://registry.coder.com/modules/coder/aws-ec2-instance-type
module "aws_ec2_instance_type" {
  source  = "registry.coder.com/coder/aws-ec2-instance-type/coder"
  version = "~> 1.0"
  default = "t3.micro"
}

provider "aws" {
  region = module.aws_region.value
}

data "coder_workspace" "me" {
}
data "coder_workspace_owner" "me" {}

data "aws_ami" "windows" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2019-English-Full-Base-*"]
  }
}

resource "coder_agent" "main" {
  arch = "amd64"
  auth = "aws-instance-identity"
  os   = "windows"
}

locals {

  # User data is used to stop/start AWS instances. See:
  # https://github.com/hashicorp/terraform-provider-aws/issues/22

  user_data_start = <<EOT
<powershell>
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
${coder_agent.main.init_script}
</powershell>
<persist>true</persist>
EOT

  user_data_end = <<EOT
<powershell>
shutdown /s
</powershell>
<persist>true</persist>
EOT
}

resource "aws_instance" "dev" {
  ami               = data.aws_ami.windows.id
  availability_zone = module.aws_region.default_availability_zone
  instance_type     = module.aws_ec2_instance_type.value

  user_data = data.coder_workspace.me.transition == "start" ? local.user_data_start : local.user_data_end
  tags = {
    Name = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
    # Required if you are using our example policy, see template README
    Coder_Provisioned = "true"
  }
  lifecycle {
    ignore_changes = [ami]
  }
}

resource "coder_metadata" "workspace_info" {
  resource_id = aws_instance.dev.id
  item {
    key   = "region"
    value = module.aws_region.value
  }
  item {
    key   = "instance type"
    value = aws_instance.dev.instance_type
  }
  item {
    key   = "disk"
    value = "${aws_instance.dev.root_block_device[0].volume_size} GiB"
  }
}
