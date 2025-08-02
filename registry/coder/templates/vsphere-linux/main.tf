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

# vSphere server configuration
data "coder_parameter" "vsphere_server" {
  name         = "vsphere_server"
  display_name = "vSphere Server"
  description  = "The vSphere server hostname or IP address"
  type         = "string"
  mutable      = false
}

data "coder_parameter" "datacenter" {
  name         = "datacenter"
  display_name = "Datacenter"
  description  = "The vSphere datacenter name"
  type         = "string"
  default      = "datacenter1"
  mutable      = false
}

data "coder_parameter" "cluster" {
  name         = "cluster"
  display_name = "Cluster"
  description  = "The vSphere cluster name"
  type         = "string"
  default      = "cluster1"
  mutable      = false
}

data "coder_parameter" "datastore" {
  name         = "datastore"
  display_name = "Datastore"
  description  = "The vSphere datastore name for VM storage"
  type         = "string"
  mutable      = false
}

data "coder_parameter" "network" {
  name         = "network"
  display_name = "Network"
  description  = "The vSphere network/port group name"
  type         = "string"
  default      = "VM Network"
  mutable      = false
}

data "coder_parameter" "template_name" {
  name         = "template_name"
  display_name = "VM Template"
  description  = "The vSphere VM template name to clone from"
  type         = "string"
  mutable      = false
}

data "coder_parameter" "cpu_count" {
  name         = "cpu_count"
  display_name = "CPU Count"
  description  = "Number of virtual CPUs for the VM"
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

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (MB)"
  description  = "Amount of memory in MB for the VM"
  default      = "4096"
  mutable      = false
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
  option {
    name  = "32 GB"
    value = "32768"
  }
}

data "coder_parameter" "disk_size" {
  name         = "disk_size"
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

# Variables for provider configuration (can be set via environment variables)
variable "vsphere_user" {
  description = "vSphere username"
  type        = string
  default     = ""
  sensitive   = true
}

variable "vsphere_password" {
  description = "vSphere password"
  type        = string
  default     = ""
  sensitive   = true
}

# vSphere provider configuration
provider "vsphere" {
  # vSphere server will be provided via environment variable VSPHERE_SERVER
  # or can be set directly here for testing
  vsphere_server = "localhost:8989"  # For Docker simulator
  user           = var.vsphere_user != "" ? var.vsphere_user : null
  password       = var.vsphere_password != "" ? var.vsphere_password : null

  # Allow unverified SSL (set to false in production)
  allow_unverified_ssl = true
}

# Coder workspace and owner data
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# vSphere data sources
data "vsphere_datacenter" "dc" {
  name = data.coder_parameter.datacenter.value
}

data "vsphere_compute_cluster" "cluster" {
  name          = data.coder_parameter.cluster.value
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_datastore" "datastore" {
  name          = data.coder_parameter.datastore.value
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_network" "network" {
  name          = data.coder_parameter.network.value
  datacenter_id = data.vsphere_datacenter.dc.id
}

data "vsphere_virtual_machine" "template" {
  name          = data.coder_parameter.template_name.value
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Coder agent for workspace connectivity
resource "coder_agent" "dev" {
  count          = data.coder_workspace.me.start_count
  arch           = "amd64"
  os             = "linux"
  startup_script = <<-EOT
    set -e
    
    # Install basic development tools
    sudo apt-get update
    sudo apt-get install -y curl wget git vim htop
    
    # Add any additional startup commands here
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

# Code Server module for web-based IDE
module "code-server" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/modules/code-server/coder"

  version = "~> 1.0"

  agent_id = coder_agent.dev[0].id
  order    = 1
}

# JetBrains Gateway module for IDE support
module "jetbrains_gateway" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/modules/jetbrains-gateway/coder"

  jetbrains_ides = ["IU", "PY", "WS", "PS", "RD", "CL", "GO", "RM"]
  default        = "IU"
  folder         = "/home/coder"
  version        = "~> 1.0"

  agent_id   = coder_agent.dev[0].id
  agent_name = "dev"
  order      = 2
}

# Local variables for VM configuration
locals {
  vm_name = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
}

# vSphere Virtual Machine
resource "vsphere_virtual_machine" "vm" {
  name             = local.vm_name
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  folder           = "coder-workspaces"

  # VM specifications
  num_cpus = tonumber(data.coder_parameter.cpu_count.value)
  memory   = tonumber(data.coder_parameter.memory.value)

  # Guest OS configuration
  guest_id  = data.vsphere_virtual_machine.template.guest_id
  firmware  = data.vsphere_virtual_machine.template.firmware
  scsi_type = data.vsphere_virtual_machine.template.scsi_type

  # Network interface configuration
  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  # Disk configuration
  disk {
    label            = "disk0"
    size             = tonumber(data.coder_parameter.disk_size.value)
    thin_provisioned = true
    unit_number      = 0
  }

  # Clone configuration from template
  clone {
    template_uuid = data.vsphere_virtual_machine.template.id

    customize {
      linux_options {
        host_name = local.vm_name
        domain    = "local"
      }

      network_interface {
        ipv4_address = "" # Use DHCP
        ipv4_netmask = 0  # Use DHCP
      }
    }
  }

  # VM will be powered on by default during creation

  # Extra configuration for better performance
  enable_disk_uuid       = true
  cpu_hot_add_enabled    = true
  memory_hot_add_enabled = true

  # VM tools configuration
  wait_for_guest_net_timeout = 5
  wait_for_guest_ip_timeout  = 5

  # Connection for agent initialization
  connection {
    type    = "ssh"
    host    = self.default_ip_address
    user    = "coder" # Adjust based on your template
    timeout = "15m"
  }

  # Install Coder agent
  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /opt/coder",
      "echo '${try(coder_agent.dev[0].init_script, "")}' | sudo tee /opt/coder/init.sh",
      "sudo chmod +x /opt/coder/init.sh",
      "sudo /opt/coder/init.sh"
    ]
  }

  tags = [
    "coder.workspace:${data.coder_workspace.me.name}",
    "coder.workspace_id:${data.coder_workspace.me.id}",
    "coder.owner:${data.coder_workspace_owner.me.name}",
    "coder.provisioned:true"
  ]

  lifecycle {
    ignore_changes = [
      clone[0].template_uuid,
      clone[0].customize[0].network_interface[0].ipv4_address,
      clone[0].customize[0].network_interface[0].ipv6_address,
    ]
  }
}

# Note: VM power management in vSphere requires additional setup
# For production use, consider implementing power management via:
# 1. vSphere API calls using local-exec provisioner
# 2. External automation tools (Ansible, PowerCLI)
# 3. Custom Terraform provider modules

# Workspace metadata display
resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = vsphere_virtual_machine.vm.id

  item {
    key   = "datacenter"
    value = data.coder_parameter.datacenter.value
  }
  item {
    key   = "cluster"
    value = data.coder_parameter.cluster.value
  }
  item {
    key   = "datastore"
    value = data.coder_parameter.datastore.value
  }
  item {
    key   = "network"
    value = data.coder_parameter.network.value
  }
  item {
    key   = "cpu_count"
    value = data.coder_parameter.cpu_count.value
  }
  item {
    key   = "memory_mb"
    value = data.coder_parameter.memory.value
  }
  item {
    key   = "disk_size_gb"
    value = data.coder_parameter.disk_size.value
  }
  item {
    key   = "vm_name"
    value = local.vm_name
  }
  item {
    key   = "ip_address"
    value = vsphere_virtual_machine.vm.default_ip_address
  }
}