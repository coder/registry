terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    incus = {
      source = "lxc/incus"
      version = "1.0.2"
    }
  }
}

provider "coder" {}

provider "incus" {
  accept_remote_certificate = true
  generate_client_certificates = true
  default_remote            = var.remote_name
  remote {
    name    = var.remote_name
    address = var.remote_address
    token   = var.remote_token
  }
}

variable "remote_name" {
  description = "Incus remote host/cluster name"
  type    = string
  default = "remote"  
}

variable "remote_address" {
  description = "Incus remote address (e.g. https://lxc.example.com:8443)"
  type    = string 
}

variable "remote_token" {
  description = "Incus remote API token with permissions to manage instances"
  type    = string
  sensitive = true
}

variable "remote_project" {
  description = "Incus remote project to use for instances"
  type    = string
  default = "default"
}

variable "remote_network" {
  description = "Incus remote network to attach instances to"
  type    = string
}

variable "remote_profiles" {
  description = "Incus remote profiles to use for instances"
  type    = list(string)
  default = []
}

variable "remote_storage_pool" {
  description = "Incus remote storage pool to use for instances"
  type    = string
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_parameter" "cpu_cores" {
  name         = "cpu_cores"
  display_name = "CPU Cores"
  type         = "number"
  default      = 2
  mutable      = true
}

data "coder_parameter" "memory_mb" {
  name         = "memory_mb"
  display_name = "Memory (MB)"
  type         = "number"
  default      = 4096
  mutable      = true
}

data "coder_parameter" "disk_size_gb" {
  name         = "disk_size_gb"
  display_name = "Disk Size (GB)"
  type         = "number"
  default      = 20
  mutable      = true
  validation {
    min       = 10
    max       = 100
    monotonic = "increasing"
  }
}

data "coder_parameter" "image" {
  name         = "image"
  display_name = "Instance Image"
  type         = "string"
  default      = "images:ubuntu/22.04/cloud"
  mutable      = true
}

data "coder_parameter" "instance_type" {
  name         = "instance_type"
  display_name = "Instance Type"
  type         = "string"
  default      = "virtual-machine"
  mutable      = true

  option {
    name = "Virtual Machine"
    value = "virtual-machine"
  }
  
  option {
    name = "LXC Container"
    value = "container"
  }
}

resource "coder_agent" "dev" {
  arch = "amd64"
  os   = "linux"

  env = {
    GIT_AUTHOR_NAME  = data.coder_workspace_owner.me.name
    GIT_AUTHOR_EMAIL = data.coder_workspace_owner.me.email
  }

  startup_script_behavior = "non-blocking"
  startup_script          = <<-EOT
    set -e
    # Add any startup scripts here
  EOT

  metadata {
    display_name = "CPU Usage"
    key          = "cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
    order        = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
    order        = 2
  }

  metadata {
    display_name = "Disk Usage"
    key          = "disk_usage"
    script       = "coder stat disk"
    interval     = 600
    timeout      = 30
    order        = 3
  }
}

locals {
  hostname         = lower(data.coder_workspace.me.name)
  vm_name          = "coder-${lower(data.coder_workspace_owner.me.name)}-${local.hostname}"
  base_user        = replace(replace(replace(lower(data.coder_workspace_owner.me.name), " ", "-"), "/", "-"), "@", "-")             # to avoid special characters in the username
  linux_user       = contains(["root", "admin", "daemon", "bin", "sys"], local.base_user) ? "${local.base_user}1" : local.base_user # to avoid conflict with system users

  rendered_user_data = templatefile("${path.module}/cloud-init/user-data.tftpl", {
    coder_token           = coder_agent.dev.token
    coder_init_script_b64 = base64encode(coder_agent.dev.init_script)
    hostname              = local.vm_name
    linux_user            = local.linux_user
  })
}

resource "incus_instance" "workspace" {
  count  = data.coder_workspace.me.start_count
  name   = local.vm_name
  image  = data.coder_parameter.image.value
  type     = data.coder_parameter.instance_type.value
  profiles = var.remote_profiles
  project  = var.remote_project
  running = true
  config = {
    "limits.cpu"     = tostring(data.coder_parameter.cpu_cores.value)
    "limits.memory"  = "${data.coder_parameter.memory_mb.value}MiB"
    "cloud-init.user-data" = local.rendered_user_data
  }

  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = var.remote_storage_pool
      size = "${data.coder_parameter.disk_size_gb.value}GiB"
    }
  }

  device {
    name = "eth-1"
    type = "nic"
    properties = {
      network = var.remote_network
    }
  }
}

module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "1.3.1"
  agent_id = coder_agent.dev.id
}