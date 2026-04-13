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
  type    = string
  default = ""
}

variable "texlive_version" {
  type    = string
  default = "latest"
}

provider "docker" {
  host = var.docker_socket != "" ? var.docker_socket : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  username    = try(data.coder_workspace_owner.me.name, "unknown")
  start_count = try(data.coder_workspace.me.start_count, 0)

  build_context_hash = sha1(join("", [
    for f in fileset("${path.module}/build", "**") :
    try(filesha1("${path.module}/build/${f}"), "")
  ]))
}

resource "coder_agent" "main" {
  arch = try(data.coder_provisioner.me.arch, "x86_64")
  os   = "linux"

  startup_script = <<-EOT
    set -e
    touch ~/.init_done
  EOT

  env = {
    HOME   = "/home/texlive"
    USER   = "texlive"
    LANG   = "C.UTF-8"
    LC_ALL = "C.UTF-8"

    GIT_AUTHOR_NAME  = coalesce(try(data.coder_workspace_owner.me.full_name, ""), local.username)
    GIT_AUTHOR_EMAIL = try(data.coder_workspace_owner.me.email, "unknown@example.com")
  }

  metadata {
    display_name = "CPU"
    key          = "cpu"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM"
    key          = "ram"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Disk"
    key          = "disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }
}

module "code-server" {
  count   = local.start_count
  source  = "registry.coder.com/coder/code-server/coder"
  version = "~> 1.0"

  agent_id = coder_agent.main.id
  folder   = "/home/texlive"
}

resource "docker_image" "texlive" {
  name = "coder-${data.coder_workspace.me.id}-texlive"

  build {
    context    = "${path.module}/build"
    dockerfile = "Dockerfile"

    build_args = {
      TEXLIVE_VERSION = var.texlive_version
    }
  }

  keep_locally = false

  triggers = {
    dir_hash        = local.build_context_hash
    texlive_version = var.texlive_version
  }
}

resource "docker_volume" "home_volume" {
  name = "coder-${try(data.coder_workspace.me.id, 0)}-home"

  labels {
    label = "coder.owner"
    value = local.username
  }

  labels {
    label = "coder.workspace_id"
    value = try(data.coder_workspace.me.id, "0")
  }

  labels {
    label = "coder.workspace_name"
    value = try(data.coder_workspace.me.name, "workspace")
  }

  lifecycle {
    ignore_changes = all
  }
}

resource "docker_container" "workspace" {
  count = local.start_count

  image    = docker_image.texlive.image_id
  name     = "coder-${local.username}-${lower(try(data.coder_workspace.me.name, "workspace"))}"
  hostname = try(data.coder_workspace.me.name, "workspace")

  entrypoint = [
    "sh",
    "-c",
    coder_agent.main.init_script
  ]

  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}"
  ]

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
    label = "coder.workspace_id"
    value = try(data.coder_workspace.me.id, "0")
  }
}
