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

# -------------------------
# PROVIDER
# -------------------------

provider "docker" {}

# -------------------------
# DATA
# -------------------------

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}
data "coder_provisioner" "me" {}

locals {
  username = data.coder_workspace_owner.me.name
}

# -------------------------
# IMAGE
# -------------------------

resource "docker_image" "workspace" {
  name = "coder-rstudio-${data.coder_workspace.me.id}"

  build {
    context = "./build"
  }
}

# -------------------------
# VOLUME
# -------------------------

resource "docker_volume" "home" {
  name = "coder-${data.coder_workspace.me.id}-home"

  lifecycle {
    ignore_changes = all
  }
}

# -------------------------
# CODER AGENT
# -------------------------

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  env = {
    HOME = "/home/rstudio"
  }
}

# -------------------------
# CONTAINER
# -------------------------

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count

  image = docker_image.workspace.image_id

  name = "coder-${local.username}-${data.coder_workspace.me.name}"

  command = [
    "bash",
    "-lc",
    <<-EOT
      set -e

      echo "[startup] starting coder agent"
      coder agent &

      echo "[startup] starting RStudio"
      rserver --auth-none=1 \
        --www-port=8787 \
        --www-address=0.0.0.0 &

      wait -n
    EOT
  ]

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}"
  ]

  volumes {
    container_path = "/home/rstudio"
    volume_name    = docker_volume.home.name
  }
}

# -------------------------
# RSTUDIO APP
# -------------------------

resource "coder_app" "rstudio" {
  agent_id     = coder_agent.main.id
  slug         = "rstudio"
  display_name = "RStudio"

  url = "http://localhost:8787"

  subdomain = true
  share     = "owner"

  healthcheck {
    url       = "http://localhost:8787"
    interval  = 5
    threshold = 30
  }
}

# -------------------------
# CODE-SERVER (MODUL)
# -------------------------

module "code-server" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/code-server/coder"
  version = "~> 1.0"

  agent_id = coder_agent.main.id
  folder   = "/home/rstudio"
}
