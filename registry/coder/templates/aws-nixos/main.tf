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
    Git remote holding the NixOS configuration. Cloned to /etc/nixos on the
    workspace, which is what makes a bare `sudo nixos-rebuild switch` work.

    Anything `git clone` accepts, so private repositories need git
    credentials on the instance rather than Nix's netrc.
  EOT
  type        = string
  default     = "https://github.com/coder/nixos-example-flake"
}

variable "flake_branch" {
  description = "Branch to track in flake_ref."
  type        = string
  default     = "main"
}

variable "flake_attr" {
  description = <<-EOT
    Which `nixosConfigurations` attribute to apply, i.e. the part after `#`
    in the flake reference. `$ARCH` is replaced with `x86_64` or `aarch64` to
    match the chosen instance type.
  EOT
  type        = string
  default     = "workspace-$ARCH"
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
  # invisible and looks like updates being ignored.
  metadata {
    key          = "nixos"
    display_name = "NixOS version"
    interval     = 60
    timeout      = 10
    # /run/current-system is the activated system; /run/booted-system is what
    # the kernel booted and still points at the previous generation after a
    # switch, which would mark every new workspace as needing a restart.
    script = <<-EOT
      version=$(nixos-version 2>/dev/null || echo unknown)
      if [ "$(readlink -f /run/current-system)" = "$(readlink -f /nix/var/nix/profiles/system)" ]; then
        echo "$version"
      else
        echo "$version (restart to apply update)"
      fi
    EOT
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

resource "coder_script" "nixos_rebuild" {
  count        = var.update_schedule == "" ? 0 : data.coder_workspace.me.start_count
  agent_id     = coder_agent.main[0].id
  display_name = "NixOS rebuild"
  cron         = var.update_schedule
  # The boot script has already switched by the time the agent exists.
  run_on_start       = false
  start_blocks_login = false
  timeout            = 3600
  log_path           = "${local.log_dir}/coder-script.log"

  script = templatefile("${path.module}/scripts/rebuild.sh.tftpl", {
    LOG_SH             = local.log_sh
    LIFECYCLE_SH       = local.lifecycle_sh
    ARG_FLAKE_REF      = local.flake_url
    ARG_FLAKE_BRANCH   = var.flake_branch
    ARG_FLAKE_ATTR     = local.flake_attr
    ARG_UPDATE_PROCESS = data.coder_parameter.update_process.value
    ARG_ACCESS_URL     = data.coder_workspace.me.access_url
    ARG_LOG_SOURCE_ID  = local.log_source_id
  })
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
  arch       = local.arch_map[data.coder_parameter.instance_type.value]
  flake_attr = replace(var.flake_attr, "$ARCH", local.arch.attr)
  log_dir    = "/var/log/coder-nixos"

  # `git clone` is what runs on the instance, so accept a Nix-style flake
  # reference too and reduce it to a plain remote: strip a `git+` scheme
  # prefix and any query string. `flake_branch` carries the ref instead.
  flake_url = replace(replace(var.flake_ref, "/^git\\+/", ""), "/\\?.*$/", "")

  # Constant, not uuid(): log sources are scoped to an agent, Coder treats a
  # repeat POST with the same id as a no-op, and a generated value would churn
  # the plan every run.
  log_source_id = "6e1f4a2c-9b3d-4c8e-8a71-5f0d2b6c4e93"

  # Sourced verbatim into the two entrypoints below. Plain shell rather than
  # templates so they stay readable and get covered by the repo's shellcheck.
  log_sh       = file("${path.module}/scripts/log.sh")
  lifecycle_sh = file("${path.module}/modules/nix/lifecycle.sh")

}

# Everything about getting Coder onto a NixOS AMI through amazon-init: the
# agent handoff, the workspace facts and the first rebuild, wrapped for EC2's
# 16 KiB user-data limit. See ./modules/amazon-init/README.md.
module "amazon_init" {
  source = "./modules/amazon-init"

  flake_ref         = local.flake_url
  flake_branch      = var.flake_branch
  flake_attr        = local.flake_attr
  access_url        = data.coder_workspace.me.access_url
  agent_token       = try(coder_agent.main[0].token, "")
  agent_init_script = try(coder_agent.main[0].init_script, "")
  log_source_id     = local.log_source_id
  workspace_name    = data.coder_workspace.me.name
  hostname          = lower(data.coder_workspace.me.name)
  owner             = data.coder_workspace_owner.me.name
  owner_name        = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  owner_email       = data.coder_workspace_owner.me.email
  log_library       = local.log_sh
  lifecycle_library = local.lifecycle_sh
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

    precondition {
      condition     = module.amazon_init.user_data_bytes < 16384
      error_message = "Rendered user-data is ${module.amazon_init.user_data_bytes} bytes; EC2 allows at most 16384."
    }
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
    value = "${local.flake_url}?ref=${var.flake_branch}#${local.flake_attr}"
  }
  item {
    key   = "Build logs location"
    value = local.log_dir
  }
}

resource "aws_ec2_instance_state" "dev" {
  instance_id = aws_instance.dev.id
  state       = data.coder_workspace.me.transition == "start" ? "running" : "stopped"
}
