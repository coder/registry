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

variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI"
  type        = string
}

variable "texlive_version" {
  default     = "latest"
  description = "The TeX Live image tag to use (e.g., TL2025-2025-01-01-08-14 or latest)"
  type        = string
}

provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  username    = try(data.coder_workspace_owner.me.name, "unknown_user")
  start_count = try(data.coder_workspace.me.start_count, 0)

  build_context_hash = sha1(join("", [
    for f in fileset("${path.module}/build", "**") :
    try(filesha1("${path.module}/build/${f}"), "")
  ]))

  date_tag = formatdate("YYYY-MM-DD-HH-mm", timestamp())

  weekly_trigger = try(
    formatdate("YYYY", timestamp()) + "-W" + tostring(ceil(tonumber(formatdate("DDD", timestamp())) / 7)),
    "2026-W01"
  )
}

resource "coder_agent" "main" {
  arch = try(data.coder_provisioner.me.arch, "x86_64")
  os   = "linux"

  startup_script = <<-EOT
    set -e
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~ 2>/dev/null || true
      touch ~/.init_done
    fi
  EOT

  env = {
    GIT_AUTHOR_NAME     = coalesce(try(data.coder_workspace_owner.me.full_name, ""), local.username)
    GIT_AUTHOR_EMAIL    = try(data.coder_workspace_owner.me.email, "unknown@example.com")
    GIT_COMMITTER_NAME  = coalesce(try(data.coder_workspace_owner.me.full_name, ""), local.username)
    GIT_COMMITTER_EMAIL = try(data.coder_workspace_owner.me.email, "unknown@example.com")
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
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }
}

module "code-server" {
  count  = local.start_count
  source = "registry.coder.com/coder/code-server/coder"

  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  order    = 1
  folder   = "/home/texlive"
}

resource "docker_image" "texlive" {
  name = "registry.example.com/texlive:TL${var.texlive_version}-${try(data.coder_workspace.me.id, 0)}-${substr(local.build_context_hash, 0, 8)}-${local.date_tag}"

  build {
    context    = "${path.module}/build"
    dockerfile = "Dockerfile"

    build_args = {
      TEXLIVE_VERSION = var.texlive_version
    }
  }

  triggers = {
    dir_hash        = local.build_context_hash
    texlive_version = var.texlive_version
    latest_rebuild  = local.weekly_trigger
  }
}

resource "docker_volume" "home_volume" {
  name = "coder-${try(data.coder_workspace.me.id, 0)}-home"

  lifecycle {
    ignore_changes = all
  }

  labels {
    label = "coder.owner"
    value = local.username
  }
  labels {
    label = "coder.owner_id"
    value = try(data.coder_workspace_owner.me.id, "0")
  }
  labels {
    label = "coder.workspace_id"
    value = try(data.coder_workspace.me.id, "0")
  }
  labels {
    label = "coder.workspace_name_at_creation"
    value = try(data.coder_workspace.me.name, "unknown_workspace")
  }
}

resource "docker_container" "workspace" {
  count    = local.start_count
  image    = docker_image.texlive.image_id
  name     = "coder-${local.username}-${lower(try(data.coder_workspace.me.name, "workspace"))}"
  hostname = try(data.coder_workspace.me.name, "workspace")

  entrypoint = [
    "sh",
    "-c",
    replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")
  ]

  env = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  volumes {
    container_path = "/home/texlive"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  labels {
    label = "coder.owner"
    value = local.username
  }
  labels {
    label = "coder.owner_id"
    value = try(data.coder_workspace_owner.me.id, "0")
  }
  labels {
    label = "coder.workspace_id"
    value = try(data.coder_workspace.me.id, "0")
  }
  labels {
    label = "coder.workspace_name"
    value = try(data.coder_workspace.me.name, "workspace")
  }
}

resource "null_resource" "cleanup_old_texlive_images" {
  triggers = {
    current_image = docker_image.texlive.name
  }

  provisioner "local-exec" {
    command = <<EOT
CURRENT_ID=$(docker inspect --format='{{.Id}}' ${docker_image.texlive.name})

docker images --format "{{.Repository}}:{{.Tag}} {{.ID}}" \
  | grep "registry.example.com/texlive:${var.texlive_version}-${try(data.coder_workspace.me.id, 0)}" \
  | grep -v "$CURRENT_ID" \
  | awk '{print $2}' \
  | xargs -r docker rmi -f
EOT
  }

  depends_on = [docker_image.texlive]
}
