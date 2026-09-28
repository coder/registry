terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.0"
    }
    aws = {
      source = "hashicorp/aws"
    }
  }
}

module "aws-region" {
  source  = "registry.coder.com/coder/aws-region/coder"
  version = "~> 1.1"
  default = "eu-west-3"
}

provider "aws" {
  region = module.aws-region.value
}

variable "flake_ref" {
  description = "Git URL of the NixOS flake; optional ?ref= selects a branch. No credentials in the URL."
  type        = string
  default     = "https://github.com/coder/nixos-example-flake"

  validation {
    condition     = can(regex("^(git\\+)?(https?|ssh)://", var.flake_ref)) && !can(regex("^(git\\+)?https?://[^/?#]*@", var.flake_ref)) && !can(regex("[[:cntrl:]]", var.flake_ref)) && !strcontains(var.flake_ref, "#") && (!strcontains(var.flake_ref, "?") || can(regex("\\?ref=[^&#?]+$", var.flake_ref)))
    error_message = "Use an http(s) or ssh Git URL without HTTP credentials, control characters, fragments, or query parameters other than ?ref=."
  }
}

variable "flake_attr" {
  description = "`nixosConfigurations` attribute to build. `$ARCH` is replaced with `x86_64` or `aarch64` to match the instance type."
  type        = string
  default     = "coder-workspace-ec2-$ARCH"
}

variable "nixos_release" {
  description = <<-EOT
    NixOS release series used to select the AMI, matched as
    `nixos/<release>*`. Only affects newly created workspaces; packages and
    the kernel come from the flake's own nixpkgs pin.
  EOT
  type        = string
  default     = "26.05"
}

module "aws-ec2-instance-type" {
  source  = "registry.coder.com/coder/aws-ec2-instance-type/coder"
  version = "~> 1.0"

  default     = "t3.medium"
  description = "Choose enough memory for NixOS builds. The smallest sizes may run out of memory."
  include = [
    "t3",
    "t4g",
    "m7g",
  ]
}

data "coder_parameter" "root_volume_size" {
  name         = "root_volume_size"
  display_name = "Root volume size (GiB)"
  description  = "Holds the Nix store as well as /home. Can be increased later."
  type         = "number"
  default      = 80
  mutable      = true

  validation {
    min       = 40
    max       = 2000
    monotonic = "increasing"
  }
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "aws_ami" "nixos" {
  most_recent = true
  filter {
    name   = "name"
    values = ["nixos/${var.nixos_release}*"]
  }
  filter {
    name   = "architecture"
    values = [local.instance.arch]
  }
  # Restrict the name match to official NixOS images.
  owners = ["427812963091"]
}

resource "coder_agent" "main" {
  count = data.coder_workspace.me.start_count
  arch  = local.instance.coder_arch
  os    = "linux"
  auth  = "token"
  # The first boot rebuilds NixOS before starting the agent.
  connection_timeout = 1200

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
    interval     = 600
    timeout      = 30
    script       = "coder stat disk --path $HOME"
  }
  # Include staged-but-not-activated generations in the agent metadata.
  metadata {
    key          = "nixos"
    display_name = "NixOS version"
    interval     = 60
    timeout      = 10
    script       = module.nix.version_command
  }
}

module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main[0].id
  order    = 1
}

# IDE binaries need nix-ld in the flake; the example enables it.
module "jetbrains-gateway" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/jetbrains-gateway/coder"
  version    = "~> 1.2"
  agent_id   = coder_agent.main[0].id
  agent_name = "main"
  arch       = local.instance.coder_arch
  folder     = "/home/coder"
  # All listed IDEs have both x86 and ARM builds.
  jetbrains_ides = ["IU", "PY", "GO", "WS"]
  default        = "IU"
  latest         = true
  order          = 2
}

module "git-config" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-config/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main[0].id
}

locals {
  instance = module.aws-ec2-instance-type.instances[module.aws-ec2-instance-type.value]
  nix_arch = local.instance.arch == "arm64" ? "aarch64" : "x86_64"
}

module "nix" {
  source = "./modules/nix"

  flake_ref  = var.flake_ref
  flake_attr = var.flake_attr
  arch       = local.nix_arch
}

module "amazon-init" {
  source = "./modules/amazon-init"

  agent_token       = try(coder_agent.main[0].token, "")
  agent_init_script = try(coder_agent.main[0].init_script, "")
  boot_script       = module.nix.boot_script
  values            = module.nix.values

  log_display_name = "NixOS"
  log_icon         = "/icon/nix.svg"
}

resource "aws_instance" "dev" {
  ami               = data.aws_ami.nixos.id
  availability_zone = module.aws-region.default_availability_zone
  instance_type     = module.aws-ec2-instance-type.value
  user_data         = module.amazon-init.user_data

  # Rotating the user-data token must not replace the persistent root disk.
  user_data_replace_on_change = false

  root_block_device {
    volume_size = data.coder_parameter.root_volume_size.value
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name              = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
    Coder_Provisioned = "true"
  }

  lifecycle {
    # New AMI releases must not replace an existing workspace and its disk.
    ignore_changes = [ami]
  }
}

resource "coder_metadata" "workspace_info" {
  resource_id = aws_instance.dev.id
  item {
    key   = "AMI"
    value = aws_instance.dev.ami
  }
  item {
    key   = "Flake URI"
    value = module.nix.flake_uri
  }
  item {
    key   = "Build logs location"
    value = module.nix.log_dir
  }
}

resource "aws_ec2_instance_state" "dev" {
  instance_id = aws_instance.dev.id
  state       = data.coder_workspace.me.transition == "start" ? "running" : "stopped"
}
