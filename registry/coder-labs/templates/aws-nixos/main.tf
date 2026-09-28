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
  # TODO: back to `registry.coder.com/coder/aws-region/coder` once 1.1.0 is
  # published. `default_availability_zone` landed in coder/registry#1138 and
  # is tagged, but the newest version the registry serves is 1.0.31, which
  # has only `value`. The tag is at least immutable, unlike a branch.
  # depth=1 because the source is the whole registry repo: 48 MiB rather
  # than 92, on every `terraform init` the provisioner runs.
  source  = "git::https://github.com/coder/registry.git//registry/coder/modules/aws-region?ref=release/coder/aws-region/v1.1.0&depth=1"
  default = "eu-west-3"
}

provider "aws" {
  region = module.aws-region.value
}

variable "flake_ref" {
  description = <<-EOT
    Git reference to the NixOS configuration, in the form `nix` itself
    accepts: `https://host/org/repo`, optionally with a `git+` prefix and a
    `?ref=` branch. Without `?ref=` the remote's default branch is used.

    The configuration must be committed -- a Git flake reference only ever
    sees committed files.
  EOT
  type        = string
  default     = "https://github.com/coder/nixos-example-flake"
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

  default = "t3.medium"
  description = trimspace(<<-EOT
    t3.medium is the smallest that works: the NixOS AMI configures no swap and
    the Nix store shares the root volume, so a rebuild that has to compile
    anything will exhaust a 1-2 GiB instance.
  EOT
  )

  # Nothing is excluded, but the families are named: the module offers `t3`
  # alone by default, and this template supports both architectures -- the
  # AMI, the agent and the flake attribute all follow the instance type, so
  # dropping the Graviton families would quietly make it x86-only.
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
    min = 40
    max = 2000
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
    values = [local.arch.ami]
  }
  # Required: aws_ami matches on a name pattern, and AMI names are not unique
  # across accounts. Without an owner filter, most_recent would happily pick
  # a stranger's image named nixos/... and boot it with the agent token.
  owners = ["427812963091"] # NixOS
}

resource "coder_agent" "main" {
  count = data.coder_workspace.me.start_count
  arch  = local.arch.agent
  os    = "linux"
  # Token rather than instance identity: the boot script needs a bearer token
  # for the agent log API anyway.
  auth = "token"
  # The first boot completes a nixos-rebuild switch before the agent exists,
  # so the default 120s looks like a failed workspace.
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
  # Makes a staged generation visible: a configuration that was built and made
  # the boot default without being activated otherwise looks exactly like
  # updates being ignored. The command comes from the nix module -- metadata
  # has to be declared on the agent, but what it means to be up to date is not
  # this file's business.
  metadata {
    key          = "nixos"
    display_name = "NixOS version"
    interval     = 60
    timeout      = 10
    script       = module.nix.version_command
  }
}

# See https://registry.coder.com/modules/coder/code-server
module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main[0].id
  order    = 1
}

# See https://registry.coder.com/modules/coder/jetbrains-gateway
#
# The IDE backend is a dynamically linked download that Gateway unpacks into
# the workspace and execs, which on NixOS needs `programs.nix-ld`. The
# reference flake enables it.
module "jetbrains-gateway" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/coder/jetbrains-gateway/coder"
  version    = "~> 1.2"
  agent_id   = coder_agent.main[0].id
  agent_name = "main"
  arch       = local.arch.agent
  # The flake names the workspace user; `coder` is the reference flake's
  # default and what the rest of this template assumes.
  folder = "/home/coder"
  # Restricted to the IDEs JetBrains publishes an aarch64 backend for, since
  # half the instance types here are Graviton.
  jetbrains_ides = ["IU", "PY", "GO", "WS"]
  default        = "IU"
  # Without this the module hands Gateway its pinned 2024.3 build numbers.
  # The cost is that a workspace build now asks data.services.jetbrains.com
  # for the current release.
  latest = true
  order  = 2
}

module "git-config" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-config/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main[0].id
}

locals {
  instance = module.aws-ec2-instance-type.instances[module.aws-ec2-instance-type.value]

  # The AMI architecture, coder_agent.arch and the flake attribute all come
  # from the instance type, so they cannot disagree. The module publishes the
  # first two spellings; the third is Nix's, and is the same distinction.
  arch = {
    agent = local.instance.coder_arch
    ami   = local.instance.arch
    attr  = local.instance.arch == "arm64" ? "aarch64" : "x86_64"
  }
}

# Everything about the flake: the checkout, the boot-time rebuild and the
# periodic one. It knows nothing about EC2 -- `boot_script` is a string for
# whoever runs scripts on the machine. See ./modules/nix/README.md.
module "nix" {
  source = "./modules/nix"

  flake_ref  = var.flake_ref
  flake_attr = var.flake_attr
  arch       = local.arch.attr
}

# Gets Coder onto the instance and runs one script on every boot. It knows
# nothing about Nix: `boot_script` is an opaque string to it, and the flake is
# applied entirely inside that string. See ./modules/amazon-init/README.md.
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

  # The agent token is inside user-data and rotates on every workspace start,
  # so user-data changes on every start. With replacement enabled, every
  # restart would destroy the root volume and with it /home and the Nix store.
  user_data_replace_on_change = false

  root_block_device {
    volume_size = data.coder_parameter.root_volume_size.value
    volume_type = "gp3"
    encrypted   = true
  }

  tags = {
    Name = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
    # Required if you are using our example policy, see template README
    Coder_Provisioned = "true"
  }

  lifecycle {
    # NixOS AMIs are republished weekly and garbage-collected after 90 days.
    # Without this, a new AMI id replaces every live workspace.
    ignore_changes = [ami]
  }
}

resource "coder_metadata" "workspace_info" {
  resource_id = aws_instance.dev.id
  item {
    key   = "AMI"
    value = data.aws_ami.nixos.name
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
