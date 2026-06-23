terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 4.0"
    }
  }
}

provider "coder" {}
provider "docker" {}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}
data "coder_provisioner" "me" {}

locals {
  ai_tools_pre_install_script = <<-EOT
    #!/bin/bash
    set -euo pipefail

    if command -v apt-get >/dev/null 2>&1; then
      (
        flock 9
        sudo apt-get update
        sudo apt-get install -y curl ca-certificates jq tmux bubblewrap
      ) 9>/tmp/coder-ai-tools-apt.lock
    fi
  EOT
}

resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = <<-EOT
    #!/bin/bash
    set -e
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~ 2>/dev/null || true
      touch ~/.init_done
    fi
  EOT

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "2_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }
}

module "codex" {
  source  = "registry.coder.com/coder-labs/codex/coder"
  version = "5.0.0"

  agent_id           = coder_agent.main.id
  enable_ai_gateway  = true
  pre_install_script = local.ai_tools_pre_install_script
}

module "claude_code" {
  source  = "registry.coder.com/coder/claude-code/coder"
  version = ">= 4.0.0"

  agent_id           = coder_agent.main.id
  enable_ai_gateway  = true
  pre_install_script = local.ai_tools_pre_install_script
}

module "omnigent" {
  source  = "registry.coder.com/coder-labs/omnigent/coder"
  version = "1.0.0"

  agent_id = coder_agent.main.id

  # Omnigent snapshots the host's available tools when the host starts. Wait for
  # Claude Code and Codex to install and configure AI Gateway first, otherwise
  # the Omnigent UI shows these harnesses as needing setup until the host restarts.
  pre_install_script = <<-EOT
    #!/bin/bash
    set -euo pipefail
    coder exp sync want coder-labs-omnigent-ai-tools ${join(" ", concat(module.claude_code.scripts, module.codex.scripts))}
    coder exp sync start coder-labs-omnigent-ai-tools
    coder exp sync complete coder-labs-omnigent-ai-tools
  EOT
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}-home"
  lifecycle {
    ignore_changes = all
  }
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

data "docker_registry_image" "workspace" {
  name = "codercom/enterprise-base:ubuntu"
}

resource "docker_image" "workspace" {
  name          = "codercom/enterprise-base@${data.docker_registry_image.workspace.sha256_digest}"
  pull_triggers = [data.docker_registry_image.workspace.sha256_digest]
  keep_locally  = true
}

resource "docker_container" "workspace" {
  count    = data.coder_workspace.me.start_count
  image    = docker_image.workspace.image_id
  name     = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = lower(data.coder_workspace.me.name)
  runtime  = "sysbox-runc"

  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
  ]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  volumes {
    container_path = "/home/coder"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}
