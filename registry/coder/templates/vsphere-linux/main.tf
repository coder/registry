terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    vsphere = {
      source  = "hashicorp/vsphere"
      version = ">= 2.0.0"
    }
  }
}

provider "vsphere" {
  # Authentication is configured via environment variables:
  # VSPHERE_USER, VSPHERE_PASSWORD, VSPHERE_SERVER
  # Or via vsphere_user, vsphere_password, vsphere_server variables
  allow_unverified_ssl = var.allow_unverified_ssl
}

variable "vsphere_datacenter" {
  type        = string
  description = "The vSphere datacenter name"
}

variable "vsphere_cluster" {
  type        = string
  description = "The vSphere cluster name"
}

variable "vsphere_datastore" {
  type        = string
  description = "The vSphere datastore name for VM storage"
}

variable "vsphere_network" {
  type        = string
  description = "The vSphere network/portgroup name"
}

variable "vsphere_template" {
  type        = string
  description = "The name of the VM template to clone from"
}

variable "vsphere_folder" {
  type        = string
  description = "The vSphere folder path for the VM (optional)"
  default     = ""
}

variable "allow_unverified_ssl" {
  type        = bool
  description = "Allow unverified SSL certificates (for self-signed certs)"
  default     = false
}

variable "vm_domain" {
  type        = string
  description = "The domain name for the VM"
  default     = "local"
}

variable "vm_dns_servers" {
  type        = list(string)
  description = "DNS servers for the VM"
  default     = ["8.8.8.8", "8.8.4.4"]
}

variable "vm_ipv4_gateway" {
  type        = string
  description = "IPv4 gateway for the VM (required if using static IP)"
  default     = ""
}

data "coder_parameter" "cpu_count" {
  name         = "cpu_count"
  display_name = "CPU Count"
  description  = "Number of vCPUs for the workspace"
  default      = "2"
  mutable      = false
  option {
    name  = "2 vCPUs"
    value = "2"
  }
  option {
    name  = "4 vCPUs"
    value = "4"
  }
  option {
    name  = "8 vCPUs"
    value = "8"
  }
  option {
    name  = "16 vCPUs"
    value = "16"
  }
}

data "coder_parameter" "memory_gb" {
  name         = "memory_gb"
  display_name = "Memory (GB)"
  description  = "Amount of memory in GB for the workspace"
  default      = "4"
  mutable      = false
  option {
    name  = "4 GB"
    value = "4"
  }
  option {
    name  = "8 GB"
    value = "8"
  }
  option {
    name  = "16 GB"
    value = "16"
  }
  option {
    name  = "32 GB"
    value = "32"
  }
}

data "coder_parameter" "disk_size_gb" {
  name         = "disk_size_gb"
  display_name = "Disk Size (GB)"
  description  = "Size of the primary disk in GB"
  default      = "50"
  mutable      = false
  option {
    name  = "50 GB"
    value = "50"
  }
  option {
    name  = "100 GB"
    value = "100"
  }
  option {
    name  = "200 GB"
    value = "200"
  }
  option {
    name  = "500 GB"
    value = "500"
  }
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# vSphere data sources
data "vsphere_datacenter" "dc" {
  name = var.vsphere_datacenter
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.vsphere_cluster
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "datastore" {
  name          = var.vsphere_datastore
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = var.vsphere_network
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template" {
  name          = var.vsphere_template
  datacenter_id = data.vsphere_datacenter.dc.id
}

locals {
  hostname   = lower(replace(data.coder_workspace.me.name, "_", "-"))
  linux_user = "coder"
  vm_name    = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
}

resource "coder_agent" "dev" {
  count          = data.coder_workspace.me.start_count
  arch           = data.vsphere_virtual_machine.template.guest_id == "ubuntu64Guest" || data.vsphere_virtual_machine.template.guest_id == "centos8_64Guest" ? "amd64" : "amd64"
  auth           = "token"
  os             = "linux"
  startup_script = <<-EOT
    set -e

    # Add any commands that should be executed at workspace startup here
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

# See https://registry.coder.com/modules/coder/code-server
module "code-server" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/modules/code-server/coder"

  version = "~> 1.0"

  agent_id   = coder_agent.dev[0].id
  agent_name = "dev"
  order      = 1
}

# See https://registry.coder.com/modules/coder/jetbrains
module "jetbrains" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/modules/coder/jetbrains/coder"
  version    = "~> 1.0"
  agent_id   = coder_agent.dev[0].id
  agent_name = "dev"
  folder     = "/home/coder"
}

resource "vsphere_virtual_machine" "dev" {
  name             = local.vm_name
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  folder           = var.vsphere_folder != "" ? var.vsphere_folder : null

  num_cpus = tonumber(data.coder_parameter.cpu_count.value)
  memory   = tonumber(data.coder_parameter.memory_gb.value) * 1024

  guest_id  = data.vsphere_virtual_machine.template.guest_id
  firmware  = data.vsphere_virtual_machine.template.firmware
  scsi_type = data.vsphere_virtual_machine.template.scsi_type

  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  disk {
    label            = "disk0"
    size             = tonumber(data.coder_parameter.disk_size_gb.value)
    thin_provisioned = data.vsphere_virtual_machine.template.disks[0].thin_provisioned
    eagerly_scrub    = data.vsphere_virtual_machine.template.disks[0].eagerly_scrub
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id

    customize {
      linux_options {
        host_name = local.hostname
        domain    = var.vm_domain
      }

      network_interface {
        # Uses DHCP by default
        # For static IP, set ipv4_address and ipv4_netmask
      }

      dns_server_list = var.vm_dns_servers
      ipv4_gateway    = var.vm_ipv4_gateway != "" ? var.vm_ipv4_gateway : null
    }
  }

  # Cloud-init user data for Coder agent installation
  extra_config = {
    "guestinfo.userdata" = base64encode(templatefile("${path.module}/cloud-init/userdata.sh.tftpl", {
      linux_user  = local.linux_user
      init_script = try(coder_agent.dev[0].init_script, "")
    }))
    "guestinfo.userdata.encoding" = "base64"
  }

  # Tags for identification
  tags = []

  custom_attributes = {
    "Coder_Provisioned" = "true"
    "Coder_Workspace"   = data.coder_workspace.me.name
    "Coder_Owner"       = data.coder_workspace_owner.me.name
  }

  lifecycle {
    ignore_changes = [
      clone[0].template_uuid,
      extra_config,
    ]
  }
}

resource "coder_metadata" "workspace_info" {
  resource_id = vsphere_virtual_machine.dev.id
  item {
    key   = "name"
    value = local.vm_name
  }
  item {
    key   = "vcpus"
    value = data.coder_parameter.cpu_count.value
  }
  item {
    key   = "memory"
    value = "${data.coder_parameter.memory_gb.value} GB"
  }
  item {
    key   = "disk"
    value = "${data.coder_parameter.disk_size_gb.value} GB"
  }
  item {
    key   = "ip_address"
    value = vsphere_virtual_machine.dev.default_ip_address
  }
}

# Control VM power state based on workspace state
resource "vsphere_virtual_machine" "power_state" {
  depends_on = [vsphere_virtual_machine.dev]

  count = data.coder_workspace.me.transition == "stop" ? 1 : 0

  # This triggers a power off when workspace transitions to stop
  # The VM is powered on automatically when workspace starts
  lifecycle {
    create_before_destroy = true
  }
}

# Use null_resource for power management
resource "null_resource" "power_management" {
  triggers = {
    vm_uuid = vsphere_virtual_machine.dev.uuid
    state   = data.coder_workspace.me.transition
  }

  # Power management is handled by vSphere - VM stays running
  # Coder agent disconnection is sufficient for workspace stop
}
