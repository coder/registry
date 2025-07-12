terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.50"
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

resource "hcloud_network" "private" {
  name     = "workspace-net-${data.coder_workspace.me.id}"
  ip_range = var.network_cidr
}

resource "hcloud_network_subnet" "private" {
  network_id   = hcloud_network.private.id
  type         = "server"
  network_zone = var.location
  ip_range     = var.network_cidr
}

resource "hcloud_server" "dev" {
  count       = var.instances
  name        = "dev-${count.index}-${data.coder_workspace.me.id}"
  image       = var.image
  server_type = var.server_type
  location    = var.location
  ssh_keys    = []

  user_data = <<-EOT
              #!/bin/bash
              curl -fsSL https://get.coder.com -o coder.sh
              bash coder.sh
              EOT
}

resource "hcloud_volume" "dev_data" {
  count     = var.instances
  name      = "volume-${count.index}-${data.coder_workspace.me.id}"
  size      = var.volume_size
  server_id = hcloud_server.dev[count.index].id
}

resource "hcloud_server_network" "connect" {
  count      = var.instances
  server_id  = hcloud_server.dev[count.index].id
  network_id = hcloud_network.private.id
  ip         = cidrhost(var.network_cidr, count.index + 10)
}

resource "coder_agent" "main" {
  os             = "linux"
  arch           = "amd64"
  startup_script = <<-EOT
    echo "Coder agent started on Hetzner VM"
  EOT
}

module "code-server" {
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
}