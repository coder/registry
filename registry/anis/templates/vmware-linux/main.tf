terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    vsphere = {
      source = "vmware/vsphere"
    }
  }
}


provider "vsphere" {
  user           = var.vsphere_username
  password       = var.vsphere_password
  vsphere_server = var.vsphere_server

  allow_unverified_ssl = true
}

variable "vsphere_username" {
  type        = string
  default     = ""
}
variable "vsphere_password" {
  type        = string
  default     = ""
  sensitive   = true
}
variable "vsphere_server" {
  type        = string
  default     = ""
}
variable "datacenter_name" {
  type        = string
  default     = ""
}
variable "cluster_name" {
  type        = string
  default     = ""
}
variable "datastore_name" {
  type        = string
  default     = ""
  sensitive   = true
}
variable "network_name" {
  type        = string
  default     = ""
}
variable "vm_template" {
  type        = string
  default     = ""
}

locals {
  vm_name           = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
  root_disk_label   = substr("${local.vm_name}-root", 0, 32)
  home_volume_label = substr("${local.vm_name}-home", 0, 32)
}

data "coder_parameter" "instance_vcpus" {
  name         = "instance_vcpus"
  display_name = "VCPUs"
  description  = "Number of VCPUs "
  type         = "number"
  default      = 1
  mutable      = true
  option {
    name  = "1 VCPUS"
    value = 1
  }
  option {
    name  = "2 VCPUS"
    value = 2
  }
  option {
    name  = "4 VCPUS"
    value = 4
  }
  option {
    name  = "8 VCPUS"
    value = 8
  }
}

data "coder_parameter" "instance_memory" {
  name         = "instance_memory"
  display_name = "Memory (GB)"
  description  = "Amount of RAM"
  type         = "number"
  default      = 2048
  mutable      = true
  option {
    name  = "1 GB"
    value = 1024
  }
  option {
    name  = "2 GB"
    value = 2048
  }
  option {
    name  = "4 GB"
    value = 4096
  }
  option {
    name  = "8 GB"
    value = 8192
  }
  option {
    name  = "16 GB"
    value = 16384
  }
  option {
    name  = "32 GB"
    value = 32768
  }
}

data "coder_parameter" "home_volume_size" {
  name         = "home_volume_size"
  display_name = "Home Volume Size (GB)"
  description  = "How large would you like your home volume to be (in GB)?"
  type         = "number"
  default      = 20
  mutable      = true

  validation {
    min       = 10
    max       = 1024
    monotonic = "increasing"
  }
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"

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
    key          = "home"
    display_name = "Home Usage"
    interval     = 600 # every 10 minutes
    timeout      = 30  # df can take a while on large filesystems
    script       = "coder stat disk --path /home/${lower(data.coder_workspace_owner.me.name)}"
  }
}

data "vsphere_datacenter" "dc" {
  name = var.datacenter_name
}

data "vsphere_datastore" "datastore" {
  name          = var.datastore_name
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster_name
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_network" "network" {
  name          = var.network_name
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_virtual_machine" "template" {
  name          = var.vm_template
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

locals {
  cloud_init_config = templatefile("cloud-init/cloud-config.yaml.tftpl", {
    hostname          = local.vm_name
    username          = lower(data.coder_workspace_owner.me.name)
    home_volume_label = local.home_volume_label
    init_script       = base64encode(coder_agent.main.init_script)
    coder_agent_token = coder_agent.main.token
  })
}

resource "vsphere_virtual_machine" "workspace" {
  name             = local.vm_name
  firmware         = data.vsphere_virtual_machine.template.firmware
  resource_pool_id = "${data.vsphere_compute_cluster.cluster.resource_pool_id}"
  datastore_id     = "${data.vsphere_datastore.datastore.id}"

  num_cpus = data.coder_parameter.instance_vcpus.value
  memory   = data.coder_parameter.instance_memory.value
  guest_id = "${data.vsphere_virtual_machine.template.guest_id}"

  scsi_type = "${data.vsphere_virtual_machine.template.scsi_type}"

  network_interface {
    network_id   = "${data.vsphere_network.network.id}"
    adapter_type = "${data.vsphere_virtual_machine.template.network_interface_types[0]}"
  }

  disk {
    label            = "disk0"
    size             = "${data.vsphere_virtual_machine.template.disks.0.size}"
  }
  disk {
    label            = local.home_volume_label
    size             = data.coder_parameter.home_volume_size.value
    unit_number      = 1
  }
  extra_config = {
    "guestinfo.userdata"          = base64encode(local.cloud_init_config)
    "guestinfo.userdata.encoding" = "base64"
  }
  clone {
   template_uuid = "${data.vsphere_virtual_machine.template.id}"
  }
}

module "code-server" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/code-server/coder"
  version = "~> 1.0"

  agent_id = coder_agent.main.id
  order    = 1
}