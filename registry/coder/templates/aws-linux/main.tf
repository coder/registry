terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    cloudinit = {
      source = "hashicorp/cloudinit"
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

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

resource "coder_agent" "dev" {
  count          = data.coder_workspace.me.start_count
  arch           = "amd64"
  auth           = "aws-instance-identity"
  os             = "linux"
  startup_script = <<-EOT
    set -e

    # Add any commands that should be executed at workspace startup (e.g install requirements, start a program, etc) here
  EOT

  metadata {
    key          = "cpu"
    display_name = "CPU Usage"
    interval     = 5
    timeout      = 5
    script       = "coder stat cpu"
  }
  metadata {
    key          = "memory"
    display_name = "Memory Usage"
    interval     = 5
    timeout      = 5
    script       = "coder stat mem"
  }
  metadata {
    key          = "disk"
    display_name = "Disk Usage"
    interval     = 600 # every 10 minutes
    timeout      = 30  # df can take a while on large filesystems
    script       = "coder stat disk --path $HOME"
  }
}

# See https://registry.coder.com/modules/coder/code-server
module "code-server" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/modules/code-server/coder"

  # This ensures that the latest non-breaking version of the module gets downloaded, you can also pin the module version to prevent breaking changes in production.
  version = "~> 1.0"

  agent_id = coder_agent.dev[0].id
  order    = 1
}

# See https://registry.coder.com/modules/coder/jetbrains
module "jetbrains" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/jetbrains/coder"
  version    = "~> 1.0"
  agent_id   = coder_agent.dev[0].id
  agent_name = "dev"
  folder     = "/home/coder"
}

locals {
  hostname   = lower(data.coder_workspace.me.name)
  linux_user = "coder"
}

data "cloudinit_config" "user_data" {
  gzip          = false
  base64_encode = false

  boundary = "//"

  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"

    content = templatefile("${path.module}/cloud-init/cloud-config.yaml.tftpl", {
      hostname    = local.hostname
      linux_user  = local.linux_user
      init_script = base64encode(try(coder_agent.dev[0].init_script, ""))
    })
  }
}

resource "aws_instance" "dev" {
  ami               = data.aws_ami.ubuntu.id
  availability_zone = module.aws_region.default_availability_zone
  instance_type     = module.aws_ec2_instance_type.value

  user_data = data.cloudinit_config.user_data.rendered
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

resource "aws_ec2_instance_state" "dev" {
  instance_id = aws_instance.dev.id
  state       = data.coder_workspace.me.transition == "start" ? "running" : "stopped"
}