terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    vsphere = {
      source = "hashicorp/vsphere"
    }
  }
}

provider "coder" {}

# vSphere provider configuration
variable "vsphere_server" {
  description = "vSphere server URL (e.g., vcenter.example.com)"
  type        = string
  sensitive   = false
}

variable "vsphere_user" {
  description = "vSphere username"
  type        = string
  sensitive   = false
}

variable "vsphere_password" {
  description = "vSphere password"
  type        = string
  sensitive   = true
}

variable "datacenter_name" {
  description = "vSphere datacenter name"
  type        = string
}

variable "cluster_name" {
  description = "vSphere cluster name"
  type        = string
}

variable "default_datastore" {
  description = "Default datastore name"
  type        = string
}

variable "default_network" {
  description = "Default network name"
  type        = string
}

variable "vm_template" {
  description = "VM template name to clone from"
  type        = string
}

provider "vsphere" {
  user                 = var.vsphere_user
  password             = var.vsphere_password
  vsphere_server       = var.vsphere_server
  allow_unverified_ssl = true
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# VM Configuration Parameters
data "coder_parameter" "cpu_count" {
  name         = "cpu_count"
  display_name = "CPU Count"
  description  = "Number of vCPUs for the virtual machine"
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

data "coder_parameter" "memory_mb" {
  name         = "memory_mb"
  display_name = "Memory (MB)"
  description  = "Amount of memory in MB for the virtual machine"
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

data "coder_parameter" "disk_size_gb" {
  name         = "disk_size_gb"
  display_name = "Disk Size (GB)"
  description  = "Size of the root disk in GB"
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

data "coder_parameter" "datastore" {
  name         = "datastore"
  display_name = "Datastore"
  description  = "vSphere datastore to store the VM"
  default      = var.default_datastore
  mutable      = false
}

data "coder_parameter" "network" {
  name         = "network"
  display_name = "Network"
  description  = "vSphere network to connect the VM"
  default      = var.default_network
  mutable      = false
}

data "coder_parameter" "vm_folder" {
  name         = "vm_folder"
  display_name = "VM Folder"
  description  = "vSphere folder to place the VM (optional)"
  default      = ""
  mutable      = false
}

# vSphere Data Sources
data "vsphere_datacenter" "dc" {
  name = var.datacenter_name
}

data "vsphere_compute_cluster" "cluster" {
  name          = var.cluster_name
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
  name          = var.vm_template
  datacenter_id = data.vsphere_datacenter.dc.id
}

# Optional VM folder
data "vsphere_folder" "vm_folder" {
  count = data.coder_parameter.vm_folder.value != "" ? 1 : 0
  path  = data.coder_parameter.vm_folder.value
}

# Coder Agent
resource "coder_agent" "main" {
  count          = data.coder_workspace.me.start_count
  arch           = "amd64"
  auth           = "token"
  os             = "linux"
  startup_script = <<-EOT
    set -e

    # Install Docker if not present
    if ! command -v docker &> /dev/null; then
      curl -fsSL https://get.docker.com -o get-docker.sh
      sudo sh get-docker.sh
      sudo usermod -aG docker $USER
    fi

    # Install common development tools
    sudo apt-get update
    sudo apt-get install -y \
      curl \
      wget \
      git \
      vim \
      nano \
      htop \
      tree \
      unzip \
      build-essential

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
    interval     = 600 # every 10 minutes
    timeout      = 30
    script       = "coder stat disk --path $HOME"
  }

  metadata {
    key          = "network"
    display_name = "Network Usage"
    interval     = 10
    timeout      = 10
    script       = <<-EOT
      #!/bin/bash
      set -e
      # Get network interface statistics
      cat /proc/net/dev | grep -E '(eth0|ens|enp)' | head -1 | awk '{print "RX: " $2/1024/1024 " MB, TX: " $10/1024/1024 " MB"}'
    EOT
  }
}

# See https://registry.coder.com/modules/code-server
module "code-server" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/modules/code-server/coder"

  # This ensures that the latest non-breaking version of the module gets downloaded
  version = "~> 1.0"

  agent_id = coder_agent.main[0].id
  order    = 1
}

# See https://registry.coder.com/modules/jetbrains-gateway
module "jetbrains_gateway" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/modules/jetbrains-gateway/coder"

  # JetBrains IDEs to make available for the user to select
  jetbrains_ides = ["IU", "PY", "WS", "PS", "RD", "CL", "GO", "RM"]
  default        = "IU"

  # Default folder to open when starting a JetBrains IDE
  folder = "/home/coder"

  version = "~> 1.0"

  agent_id   = coder_agent.main[0].id
  agent_name = "main"
  order      = 2
}

locals {
  vm_name    = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
  linux_user = "coder"
}

# vSphere Virtual Machine
resource "vsphere_virtual_machine" "vm" {
  count = data.coder_workspace.me.start_count

  name             = local.vm_name
  resource_pool_id = data.vsphere_compute_cluster.cluster.resource_pool_id
  datastore_id     = data.vsphere_datastore.datastore.id
  folder           = data.coder_parameter.vm_folder.value != "" ? data.vsphere_folder.vm_folder[0].path : null

  num_cpus               = tonumber(data.coder_parameter.cpu_count.value)
  memory                 = tonumber(data.coder_parameter.memory_mb.value)
  guest_id               = data.vsphere_virtual_machine.template.guest_id
  firmware               = data.vsphere_virtual_machine.template.firmware
  scsi_type              = data.vsphere_virtual_machine.template.scsi_type
  hardware_version       = data.vsphere_virtual_machine.template.hardware_version
  wait_for_guest_net_timeout = 300

  # Enable CPU and Memory hot add
  cpu_hot_add_enabled    = true
  cpu_hot_remove_enabled = true
  memory_hot_add_enabled = true

  network_interface {
    network_id   = data.vsphere_network.network.id
    adapter_type = data.vsphere_virtual_machine.template.network_interface_types[0]
  }

  disk {
    label            = "${local.vm_name}-disk0"
    size             = tonumber(data.coder_parameter.disk_size_gb.value)
    eagerly_scrub    = data.vsphere_virtual_machine.template.disks.0.eagerly_scrub
    thin_provisioned = data.vsphere_virtual_machine.template.disks.0.thin_provisioned
  }

  clone {
    template_uuid = data.vsphere_virtual_machine.template.id

    customize {
      linux_options {
        host_name = local.vm_name
        domain    = "local"
      }

      network_interface {
        # Use DHCP by default - can be customized as needed
      }
    }
  }

  # Add custom attributes for Coder identification
  extra_config = {
    "coder.workspace.owner" = data.coder_workspace_owner.me.name
    "coder.workspace.name"  = data.coder_workspace.me.name
    "coder.workspace.id"    = data.coder_workspace.me.id
  }

  # Lifecycle management
  lifecycle {
    ignore_changes = [
      annotation,
      clone[0].template_uuid,
      clone[0].customize[0].dns_server_list,
      clone[0].customize[0].dns_suffix_list,
    ]
  }

  # Initialize the Coder agent
  provisioner "remote-exec" {
    connection {
      type = "ssh"
      host = self.default_ip_address
      user = "root" # Adjust based on your template
      # You may need to configure SSH key or password authentication
    }

    inline = [
      "# Create coder user if it doesn't exist",
      "if ! id -u ${local.linux_user} >/dev/null 2>&1; then",
      "  useradd -m -s /bin/bash ${local.linux_user}",
      "  echo '${local.linux_user} ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/coder-user",
      "fi",
      "",
      "# Install Coder agent as the coder user",
      "sudo -u ${local.linux_user} bash -c '${coder_agent.main[0].init_script}'",
    ]
  }
}

# VM Power Management
resource "vsphere_virtual_machine_snapshot" "workspace_snapshot" {
  count              = data.coder_workspace.me.transition == "stop" ? 1 : 0
  virtual_machine_id = vsphere_virtual_machine.vm[0].id
  snapshot_name      = "coder-workspace-stop-${formatdate("YYYY-MM-DD-hhmm", timestamp())}"
  description        = "Automatic snapshot created when stopping Coder workspace"
  memory             = false
  quiesce            = true
}

# Metadata for workspace information
resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = vsphere_virtual_machine.vm[0].id

  item {
    key   = "vCPUs"
    value = data.coder_parameter.cpu_count.value
  }

  item {
    key   = "Memory"
    value = "${data.coder_parameter.memory_mb.value} MB"
  }

  item {
    key   = "Disk Size"
    value = "${data.coder_parameter.disk_size_gb.value} GB"
  }

  item {
    key   = "Datastore"
    value = data.coder_parameter.datastore.value
  }

  item {
    key   = "Network"
    value = data.coder_parameter.network.value
  }

  item {
    key   = "IP Address"
    value = vsphere_virtual_machine.vm[0].default_ip_address
  }

  item {
    key   = "vSphere UUID"
    value = vsphere_virtual_machine.vm[0].uuid
  }
}

# Additional disk for data persistence (optional)
resource "vsphere_virtual_disk" "data_disk" {
  count            = data.coder_workspace.me.start_count > 0 && data.coder_parameter.disk_size_gb.value != "50" ? 1 : 0
  size             = 100 # Additional 100GB data disk
  vmdk_path        = "${local.vm_name}-data.vmdk"
  datacenter       = var.datacenter_name
  datastore        = data.coder_parameter.datastore.value
  type             = "thin"
  adapter_type     = "lsilogic"
  create_directories = true
}

# Attach additional disk to VM
resource "vsphere_virtual_machine_disk" "data_disk_attachment" {
  count              = length(vsphere_virtual_disk.data_disk)
  virtual_machine_id = vsphere_virtual_machine.vm[0].id
  virtual_disk_id    = vsphere_virtual_disk.data_disk[0].id
  unit_number        = 1
}

# Output important information
output "vm_ip_address" {
  description = "IP address of the created VM"
  value       = data.coder_workspace.me.start_count > 0 ? vsphere_virtual_machine.vm[0].default_ip_address : null
}

output "vm_uuid" {
  description = "UUID of the created VM"
  value       = data.coder_workspace.me.start_count > 0 ? vsphere_virtual_machine.vm[0].uuid : null
}

output "datastore_used" {
  description = "Datastore where the VM is stored"
  value       = data.coder_parameter.datastore.value
}
