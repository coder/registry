terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

locals {
  username = data.coder_workspace_owner.me.name
}

variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI"
  type        = string
}

variable "texlive_version" {
  default     = "2026"
  description = "The TeX Live image tag to use (e.g., TL2026-2026-01-01-08-14 or latest)"
  type        = string
}

provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Docker image for TeX Live 2026
resource "docker_image" "texlive" {
  name = "texlive:${var.texlive_version}"
  build {
    context    = "./build"
    dockerfile = "Dockerfile"
    build_args = {
      TEXLIVE_VERSION = var.texlive_version
    }
  }
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle { ignore_changes = all }
  labels = {
    "coder.owner"                  = data.coder_workspace_owner.me.name
    "coder.owner_id"               = data.coder_workspace_owner.me.id
    "coder.workspace_id"           = data.coder_workspace.me.id
    "coder.workspace_name_at_creation" = data.coder_workspace.me.name
  }
}

resource "docker_container" "texlive_workspace" {
  count    = data.coder_workspace.me.start_count
  image    = docker_image.texlive.image_id
  name     = "texlive-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  hostname = data.coder_workspace.me.name
  env      = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]

  volumes {
    container_path = "/home/texlive"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  labels = {
    "coder.owner"        = data.coder_workspace_owner.me.name
    "coder.owner_id"     = data.coder_workspace_owner.me.id
    "coder.workspace_id" = data.coder_workspace.me.id
    "coder.workspace_name" = data.coder_workspace.me.name
  }
}

# Optional: Coder agent for workspace metrics
resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = <<-EOT
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
}

# Code Server — served through the Coder agent
module "code-server" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/code-server/coder"
  version = "~> 1.0"

  agent_id = coder_agent.main.id
  order    = 1
  folder   = "/home/texlive"
}

# Coder App für TeX Live 2026 + Code Server
resource "coder_app" "texlive" {
  agent_id     = coder_agent.main.id
  slug         = "texlive"
  display_name = "TeX Live 2026"
  url          = "http://localhost:8080"   # Code Server Port
  icon         = "/icon/texlive.svg"       # Icon im Container
  subdomain    = true
  share        = "owner"
  order        = 1

  labels = {
    "module"     = "docker-texlive"
    "workspace"  = data.coder_workspace.me.name
    "owner"      = data.coder_workspace_owner.me.name
  }
}
