terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.66"
    }
  }
}

data "coder_parameter" "proxmox_node" {
  name         = "proxmox_node"
  display_name = "Proxmox Node"
  description  = "Which Proxmox node should your workspace be deployed to?"
  default      = "pve"
  mutable      = false
}

data "coder_parameter" "vm_template" {
  name         = "vm_template"
  display_name = "VM Template"
  description  = "Which VM template should be used for the workspace?"
  default      = "ubuntu-22.04-cloudinit"
  mutable      = false
  option {
    name  = "Ubuntu 22.04 LTS"
    value = "ubuntu-22.04-cloudinit"
    icon  = "/icon/ubuntu.svg"
  }
  option {
    name  = "Ubuntu 20.04 LTS"
    value = "ubuntu-20.04-cloudinit"
    icon  = "/icon/ubuntu.svg"
  }
  option {
    name  = "Debian 12"
    value = "debian-12-cloudinit"
    icon  = "/icon/debian.svg"
  }
}

data "coder_parameter" "cpu_cores" {
  name         = "cpu_cores"
  display_name = "CPU Cores"
  description  = "How many CPU cores should your workspace have?"
  default      = "2"
  mutable      = true
  option {
    name  = "2 Cores"
    value = "2"
  }
  option {
    name  = "4 Cores"
    value = "4"
  }
  option {
    name  = "6 Cores"
    value = "6"
  }
  option {
    name  = "8 Cores"
    value = "8"
  }
}

data "coder_parameter" "memory_mb" {
  name         = "memory_mb"
  display_name = "Memory (MB)"
  description  = "How much memory should your workspace have?"
  default      = "2048"
  mutable      = true
  option {
    name  = "2 GB"
    value = "2048"
  }
  option {
    name  = "4 GB"
    value = "4096"
  }
  option {
    name  = "8 GB"
    value = "8192"
  }
  option {
    name  = "16 GB"
    value = "16384"
  }
}

data "coder_parameter" "disk_size" {
  name         = "disk_size"
  display_name = "Disk Size (GB)"
  description  = "How much disk space should your workspace have?"
  default      = "32"
  mutable      = true
  option {
    name  = "32 GB"
    value = "32"
  }
  option {
    name  = "64 GB"
    value = "64"
  }
  option {
    name  = "128 GB"
    value = "128"
  }
  option {
    name  = "256 GB"
    value = "256"
  }
}

data "coder_parameter" "datastore" {
  name         = "datastore"
  display_name = "Storage Datastore"
  description  = "Which Proxmox datastore should be used for VM storage?"
  default      = "local-lvm"
  mutable      = false
  option {
    name  = "Local LVM"
    value = "local-lvm"
  }
  option {
    name  = "Local ZFS"
    value = "local-zfs"
  }
  option {
    name  = "NFS Storage"
    value = "nfs-storage"
  }
}

data "coder_parameter" "network_bridge" {
  name         = "network_bridge"
  display_name = "Network Bridge"
  description  = "Which network bridge should the VM use?"
  default      = "vmbr0"
  mutable      = false
  option {
    name  = "Default Bridge (vmbr0)"
    value = "vmbr0"
  }
  option {
    name  = "Bridge 1 (vmbr1)"
    value = "vmbr1"
  }
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  username = data.coder_workspace_owner.me.name
  vm_name  = "coder-${local.username}-${data.coder_workspace.me.name}"
  vm_id    = 1000 + (length(local.vm_name) * 100) + (length(local.username) * 10)
}

resource "coder_agent" "main" {
  count          = data.coder_workspace.me.start_count
  arch           = "amd64"
  os             = "linux"
  startup_script = <<-EOT
    set -e

    sudo systemctl enable --now qemu-guest-agent

    if [ ! -f ~/.init_done ]; then
      sudo apt-get update
      sudo apt-get install -y curl wget git build-essential
      touch ~/.init_done
    fi
  EOT

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
}

module "code-server" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/modules/code-server/coder"

  version = "~> 1.0"

  agent_id = coder_agent.main[0].id
  order    = 1
}

module "jetbrains_gateway" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/modules/jetbrains-gateway/coder"

  jetbrains_ides = ["IU", "PY", "WS", "GO", "CL"]
  default        = "IU"
  folder         = "/home/coder"
  version        = "~> 1.0"

  agent_id   = coder_agent.main[0].id
  agent_name = "main"
  order      = 2
}

resource "proxmox_virtual_environment_vm" "dev" {
  name        = local.vm_name
  description = "Coder workspace for ${local.username}"
  tags        = ["coder", "terraform", data.coder_workspace.me.name]
  node_name   = data.coder_parameter.proxmox_node.value
  vm_id       = local.vm_id

  agent {
    enabled = true
    timeout = "15m"
  }

  cpu {
    cores = tonumber(data.coder_parameter.cpu_cores.value)
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = tonumber(data.coder_parameter.memory_mb.value)
    floating  = tonumber(data.coder_parameter.memory_mb.value)
  }

  network_device {
    bridge = data.coder_parameter.network_bridge.value
    model  = "virtio"
  }

  disk {
    datastore_id = data.coder_parameter.datastore.value
    interface    = "virtio0"
    size         = tonumber(data.coder_parameter.disk_size.value)
    file_format  = "raw"
    cache        = "writeback"
    iothread     = true
    ssd          = true
    discard      = "on"
  }

  initialization {
    datastore_id = data.coder_parameter.datastore.value
    interface    = "ide2"

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    user_account {
      password = random_password.vm_password.result
      username = "coder"
    }

    user_data_file_id = proxmox_virtual_environment_file.cloud_config.id
  }

  clone {
    vm_id = data.coder_parameter.vm_template.value
    full  = true
  }

  lifecycle {
    ignore_changes = [
      initialization[0].user_data_file_id,
    ]
  }

  stop_on_destroy = true
}

resource "random_password" "vm_password" {
  length  = 16
  special = true
}

resource "proxmox_virtual_environment_file" "cloud_config" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = data.coder_parameter.proxmox_node.value

  source_raw {
    data = templatefile("${path.module}/cloud-config.yaml.tftpl", {
      username    = "coder"
      password    = random_password.vm_password.result
      init_script = base64encode(try(coder_agent.main[0].init_script, ""))
    })
    file_name = "coder-cloud-config-${local.vm_name}.yaml"
  }
}

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = proxmox_virtual_environment_vm.dev.id

  item {
    key   = "node"
    value = data.coder_parameter.proxmox_node.value
  }
  item {
    key   = "vm_id"
    value = tostring(local.vm_id)
  }
  item {
    key   = "cpu_cores"
    value = data.coder_parameter.cpu_cores.value
  }
  item {
    key   = "memory"
    value = "${data.coder_parameter.memory_mb.value} MB"
  }
  item {
    key   = "disk_size"
    value = "${data.coder_parameter.disk_size.value} GB"
  }
  item {
    key   = "datastore"
    value = data.coder_parameter.datastore.value
  }
  item {
    key   = "network_bridge"
    value = data.coder_parameter.network_bridge.value
  }
}