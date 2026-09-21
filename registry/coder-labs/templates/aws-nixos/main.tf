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

module "aws_region" {
  source  = "registry.coder.com/coder/aws-region/coder"
  version = "~> 1.0"
  default = "eu-west-3"
}

provider "aws" {
  region = module.aws_region.value
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
  default     = "coder-workspace-$ARCH"
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

variable "update_schedule" {
  description = <<-EOT
    Cron schedule for the periodic `nixos-rebuild`, or empty to disable.

    SIX fields with seconds first, in the workspace's timezone. A five field
    expression is silently misinterpreted rather than rejected, and
    descriptors like `@daily` pass validation then fail on the agent.
  EOT
  type        = string
  default     = "0 0 4 * * *"

  validation {
    condition     = var.update_schedule == "" || length(split(" ", trimspace(var.update_schedule))) == 6
    error_message = "update_schedule must be a 6-field cron expression (seconds first), or empty."
  }
}

data "coder_parameter" "instance_type" {
  name         = "instance_type"
  display_name = "Instance type"
  description  = <<-EOT
    The smallest option is t3.medium on purpose: the NixOS AMI configures no
    swap and the Nix store shares the root volume, so a rebuild that has to
    compile anything will exhaust a 1-2 GiB instance.
  EOT
  default      = "t3.medium"
  mutable      = false

  option {
    name  = "2 vCPU, 4 GiB RAM"
    value = "t3.medium"
  }
  option {
    name  = "2 vCPU, 8 GiB RAM"
    value = "t3.large"
  }
  option {
    name  = "4 vCPU, 16 GiB RAM"
    value = "t3.xlarge"
  }
  option {
    name  = "8 vCPU, 32 GiB RAM"
    value = "t3.2xlarge"
  }
  option {
    name  = "2 vCPU, 4 GiB RAM (Graviton)"
    value = "t4g.medium"
  }
  option {
    name  = "2 vCPU, 8 GiB RAM (Graviton)"
    value = "m7g.large"
  }
  option {
    name  = "4 vCPU, 16 GiB RAM (Graviton)"
    value = "m7g.xlarge"
  }
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

data "coder_parameter" "update_process" {
  name         = "update_process"
  display_name = "Configuration updates"
  description  = <<-EOT
    How a periodic `nixos-rebuild` is applied while the workspace is running.
    `boot` stages the new configuration without activating it, so nothing
    restarts under you; `switch` activates it immediately.
  EOT
  type         = "string"
  default      = "boot"
  mutable      = true

  option {
    name  = "Apply on next restart (boot)"
    value = "boot"
  }
  option {
    name  = "Apply immediately (switch)"
    value = "switch"
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
  # Makes `update_process = boot` visible; a staged generation is otherwise
  # invisible and looks like updates being ignored. The command comes from the
  # nix module -- metadata has to be declared on the agent, but what it means
  # to be up to date is not this file's business.
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
module "jetbrains_gateway" {
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

# Git authorship, which the NixOS configuration deliberately does not set: it
# is per-workspace state a flake has no pure way to learn.
#
# See https://registry.coder.com/modules/coder/git-config
module "git-config" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-config/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main[0].id
}

locals {
  # One map so the AMI architecture, coder_agent.arch and the flake attribute
  # cannot disagree.
  arch_map = {
    "t3.medium"  = { agent = "amd64", ami = "x86_64", attr = "x86_64" }
    "t3.large"   = { agent = "amd64", ami = "x86_64", attr = "x86_64" }
    "t3.xlarge"  = { agent = "amd64", ami = "x86_64", attr = "x86_64" }
    "t3.2xlarge" = { agent = "amd64", ami = "x86_64", attr = "x86_64" }
    "t4g.medium" = { agent = "arm64", ami = "arm64", attr = "aarch64" }
    "m7g.large"  = { agent = "arm64", ami = "arm64", attr = "aarch64" }
    "m7g.xlarge" = { agent = "arm64", ami = "arm64", attr = "aarch64" }
  }
  arch = local.arch_map[data.coder_parameter.instance_type.value]
}

# Everything about the flake: the checkout, the boot-time rebuild and the
# periodic one. It knows nothing about EC2 -- `boot_script` is a string for
# whoever runs scripts on the machine. See ./modules/nix/README.md.
module "nix" {
  source = "./modules/nix"

  # Empty while the workspace is stopped, when there is no agent to attach the
  # periodic rebuild to. The module skips the script in that case.
  agent_id = try(coder_agent.main[0].id, "")

  flake_ref       = var.flake_ref
  flake_attr      = var.flake_attr
  arch            = local.arch.attr
  update_schedule = var.update_schedule
  update_process  = data.coder_parameter.update_process.value
}

# Gets Coder onto the instance and runs one script on every boot. It knows
# nothing about Nix: `boot_script` is an opaque string to it, and the flake is
# applied entirely inside that string. See ./modules/amazon-init/README.md.
module "amazon_init" {
  source = "./modules/amazon-init"

  agent_token       = try(coder_agent.main[0].token, "")
  agent_init_script = try(coder_agent.main[0].init_script, "")
  boot_script       = module.nix.boot_script

  log_display_name = "NixOS"
  log_icon         = "/icon/nix.svg"
}

resource "aws_instance" "dev" {
  ami               = data.aws_ami.nixos.id
  availability_zone = "${module.aws_region.value}a"
  instance_type     = data.coder_parameter.instance_type.value
  user_data         = module.amazon_init.user_data

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
