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
  repo_ready_sync_name = "matifali-omnigent-git-clone"

  ai_tools_pre_install_commands = <<-EOT
    missing_packages=()
    command -v curl >/dev/null 2>&1 || missing_packages+=(curl)
    command -v jq >/dev/null 2>&1 || missing_packages+=(jq)
    command -v tmux >/dev/null 2>&1 || missing_packages+=(tmux)
    command -v bwrap >/dev/null 2>&1 || missing_packages+=(bubblewrap)

    need_node=false
    if ! command -v node >/dev/null 2>&1; then
      need_node=true
    elif ! node -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 22 ? 0 : 1)' >/dev/null 2>&1; then
      need_node=true
    fi

    if [ "$${#missing_packages[@]}" -eq 0 ] && [ "$${need_node}" = false ]; then
      exit 0
    fi

    if ! command -v apt-get >/dev/null 2>&1; then
      echo "ERROR: missing required tools and apt-get is not available to install them." >&2
      printf 'Missing packages: %s\n' "$${missing_packages[*]:-none}" >&2
      printf 'Need Node.js 22+: %s\n' "$${need_node}" >&2
      exit 1
    fi

    (
      flock 9
      sudo apt-get update

      if [ "$${need_node}" = true ]; then
        if ! command -v curl >/dev/null 2>&1; then
          sudo apt-get install -y curl ca-certificates
        fi
        curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
        sudo apt-get install -y nodejs
      fi

      if [ "$${#missing_packages[@]}" -gt 0 ]; then
        sudo apt-get install -y ca-certificates "$${missing_packages[@]}"
      fi
    ) 9>/tmp/coder-ai-tools-apt.lock
  EOT

  codex_pre_install_script = <<-EOT
    #!/bin/bash
    set -euo pipefail
    coder exp sync want coder-labs-codex-repo-ready ${local.repo_ready_sync_name}
    coder exp sync start coder-labs-codex-repo-ready
    coder exp sync complete coder-labs-codex-repo-ready

    ${local.ai_tools_pre_install_commands}
  EOT

  claude_code_pre_install_script = <<-EOT
    #!/bin/bash
    set -euo pipefail
    coder exp sync want coder-claude-code-repo-ready ${local.repo_ready_sync_name}
    coder exp sync start coder-claude-code-repo-ready
    coder exp sync complete coder-claude-code-repo-ready

    ${local.ai_tools_pre_install_commands}
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

module "git_clone" {
  source  = "registry.coder.com/coder/git-clone/coder"
  version = "~> 2.0"

  agent_id    = coder_agent.main.id
  url         = "https://github.com/coder/coder"
  base_dir    = "/home/coder/workspace"
  folder_name = "coder"
  extra_args  = ["--depth=1"]

  post_clone_script = <<-EOT
    #!/bin/bash
    set -euo pipefail
    coder exp sync start ${local.repo_ready_sync_name}
    coder exp sync complete ${local.repo_ready_sync_name}
  EOT
}

module "codex" {
  source  = "registry.coder.com/coder-labs/codex/coder"
  version = "~> 5.2, >= 5.2.1"

  agent_id           = coder_agent.main.id
  workdir            = module.git_clone.repo_dir
  enable_ai_gateway  = true
  pre_install_script = local.codex_pre_install_script
}

module "claude_code" {
  source  = "registry.coder.com/coder/claude-code/coder"
  version = "~> 5.2"

  agent_id           = coder_agent.main.id
  workdir            = module.git_clone.repo_dir
  enable_ai_gateway  = true
  pre_install_script = local.claude_code_pre_install_script
}

module "omnigent" {
  source  = "registry.coder.com/matifali/omnigent/coder"
  version = "~> 0.0, >= 0.0.1"

  agent_id = coder_agent.main.id

  # Omnigent snapshots the host's available tools when the host starts. Wait for
  # Claude Code and Codex to install and configure AI Gateway first, otherwise
  # the Omnigent UI shows these harnesses as needing setup until the host restarts.
  pre_install_script = <<-EOT
    #!/bin/bash
    set -euo pipefail
    coder exp sync want matifali-omnigent-ai-tools ${join(" ", concat(module.claude_code.scripts, module.codex.scripts))}
    coder exp sync start matifali-omnigent-ai-tools
    coder exp sync complete matifali-omnigent-ai-tools
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
