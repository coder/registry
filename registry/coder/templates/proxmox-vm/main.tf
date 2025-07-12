<!-- filepath: /home/pranjal/Desktop/Github Repo/registry/registry/coder/templates/proxmox-vm/main.tf -->
terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    proxmox = {
      source  = "telmate/proxmox"
      version = "~> 3.0"
    }
    cloudinit = {
      source = "hashicorp/cloudinit"
    }
  }
}

provider "coder" {}

# Variables for Proxmox configuration
variable "proxmox_api_url" {
  description = "Proxmox API URL (e.g., https://proxmox-server:8006/api2/json)"
  type        = string
  default     = ""
}

variable "proxmox_node" {
  description = "Proxmox VE node name where VMs will be created"
  type        = string
  default     = "pve"
}

variable "vm_template" {
  description = "VM template name to clone from"
  type        = string
  default     = "ubuntu-22.04-cloud"
}

variable "storage" {
  description = "Storage backend for VM disks"
  type        = string
  default     = "local-lvm"
}

variable "network_bridge" {
  description = "Network bridge to connect VMs to"
  type        = string
  default     = "vmbr0"
}

# Proxmox provider configuration following official documentation
provider "proxmox" {
  # API URL can be set via PM_API_URL environment variable or variable
  pm_api_url = var.proxmox_api_url != "" ? var.proxmox_api_url : null
  
  # Authentication via API token (recommended):
  # Set these environment variables:
  # PM_API_TOKEN_ID='terraform-prov@pve!mytoken'
  # PM_API_TOKEN_SECRET="your-token-secret"
  #
  # Or via username/password:
  # PM_USER="terraform-prov@pve"
  # PM_PASS="password"
  
  # TLS settings
  pm_tls_insecure = true  # Allow self-signed certificates (common in Proxmox)
  
  # Performance settings
  pm_parallel = 2    # Allow 2 simultaneous operations
  pm_timeout  = 600  # 10 minute timeout for API calls
  
  # Optional: Enable debugging
  pm_debug = false
  
  # Optional: Enable logging for troubleshooting
  pm_log_enable = false
  pm_log_file   = "terraform-plugin-proxmox.log"
  
  # Minimum permission check
  pm_minimum_permission_check = true
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# User parameters for VM configuration
data "coder_parameter" "cpu_cores" {
  name         = "cpu_cores"
  display_name = "CPU Cores"
  description  = "Number of CPU cores for the VM"
  type         = "number"
  default      = 2
  icon         = "/icon/memory.svg"
  mutable      = true
  validation {
    min = 1
    max = 16
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (MB)"
  description  = "Amount of memory in MB"
  type         = "number"
  default      = 2048
  icon         = "/icon/memory.svg"
  mutable      = true
  validation {
    min = 512
    max = 32768
  }
}

data "coder_parameter" "disk_size" {
  name         = "disk_size"
  display_name = "Disk Size (GB)"
  description  = "Size of the VM disk in GB"
  type         = "number"
  default      = 20
  icon         = "/emojis/1f4be.png"
  mutable      = false
  validation {
    min = 10
    max = 500
  }
}

data "coder_parameter" "proxmox_node" {
  name         = "proxmox_node"
  display_name = "Proxmox Node"
  description  = "Which Proxmox node should host the VM?"
  type         = "string"
  default      = var.proxmox_node
  mutable      = false
}

resource "coder_agent" "main" {
  arch           = "amd64"
  os             = "linux"
  startup_script = <<-EOT
    set -e

    # Wait for cloud-init to complete
    cloud-init status --wait

    # Install development tools
    sudo apt-get update
    sudo apt-get install -y curl wget git build-essential

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
    script       = "coder stat disk --path /home/coder"
  }
}

# See https://registry.coder.com/modules/coder/code-server
module "code-server" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/coder/code-server/coder"
  
  version = "~> 1.0"
  agent_id = coder_agent.main.id
  order    = 1
}

# See https://registry.coder.com/modules/coder/jetbrains-gateway
module "jetbrains_gateway" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/coder/jetbrains-gateway/coder"

  jetbrains_ides = ["IU", "PY", "WS", "PS", "RD", "CL", "GO", "RM"]
  default        = "IU"
  folder         = "/home/coder"
  
  version = "~> 1.0"
  agent_id   = coder_agent.main.id
  agent_name = "main"
  order      = 2
}

locals {
  vm_name     = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
  linux_user  = "coder"
  hostname    = lower(data.coder_workspace.me.name)
}

# Cloud-init configuration
data "cloudinit_config" "user_data" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    content = yamlencode({
      hostname = local.hostname
      users = [{
        name                = local.linux_user
        groups              = ["sudo", "docker"]
        sudo                = "ALL=(ALL) NOPASSWD:ALL"
        shell               = "/bin/bash"
        lock_passwd         = true
        ssh_authorized_keys = []
      }]
      packages = [
        "curl",
        "wget",
        "git",
        "build-essential",
        "qemu-guest-agent"
      ]
      runcmd = [
        "systemctl enable qemu-guest-agent",
        "systemctl start qemu-guest-agent",
        "usermod -aG docker ${local.linux_user}",
        # Run Coder agent init script
        "su - ${local.linux_user} -c '${coder_agent.main.init_script}'"
      ]
      write_files = [{
        path    = "/etc/systemd/system/coder-agent.service"
        content = <<-EOT
          [Unit]
          Description=Coder Agent
          After=network-online.target
          Wants=network-online.target

          [Service]
          Type=notify
          User=${local.linux_user}
          WorkingDirectory=/home/${local.linux_user}
          Environment=CODER_AGENT_TOKEN=${coder_agent.main.token}
          ExecStart=${coder_agent.main.init_script}
          Restart=always
          RestartSec=10

          [Install]
          WantedBy=multi-user.target
        EOT
      }]
    })
  }
}

# Create cloud-init user data file
resource "proxmox_file" "cloud_init_user_data" {
  content_type = "snippets"
  datastore_id = "local"
  node_name    = data.coder_parameter.proxmox_node.value
  
  source_raw {
    data      = data.cloudinit_config.user_data.rendered
    file_name = "coder-${data.coder_workspace.me.id}-user.yml"
  }
}

# Create the VM using proxmox_vm_qemu resource
resource "proxmox_vm_qemu" "workspace" {
  count       = data.coder_workspace.me.start_count
  name        = local.vm_name
  target_node = data.coder_parameter.proxmox_node.value
  
  # Clone from template
  clone      = var.vm_template
  full_clone = true
  
  # VM Configuration
  cores   = data.coder_parameter.cpu_cores.value
  memory  = data.coder_parameter.memory.value
  sockets = 1
  
  # Enable Qemu Guest Agent for better integration
  agent = 1
  
  # Operating system type
  os_type = "cloud-init"
  
  # Cloud-init configuration
  cloudinit_cdrom_storage = var.storage
  cicustom                = "user=local:snippets/coder-${data.coder_workspace.me.id}-user.yml"
  
  # Network configuration
  network {
    bridge = var.network_bridge
    model  = "virtio"
  }
  
  # Disk configuration following provider documentation format
  disks {
    scsi {
      scsi0 {
        disk {
          size    = data.coder_parameter.disk_size.value
          storage = var.storage
          format  = "raw"  # Explicitly set format
        }
      }
    }
  }
  
  # Boot settings
  boot    = "order=scsi0"
  onboot  = false
  startup = ""
  
  # VM lifecycle management
  lifecycle {
    ignore_changes = [
      network,
      desc,
      numa,
      hotplug,
      disk,  # Prevent disk recreation
    ]
  }
  
  # Tags for identification (supported in newer Proxmox versions)
  tags = "coder,workspace,${data.coder_workspace_owner.me.name}"
  
  # Depends on cloud-init file being created first
  depends_on = [proxmox_file.cloud_init_user_data]
}

# VM power management based on workspace state
resource "null_resource" "vm_power_management" {
  count = data.coder_workspace.me.start_count
  
  # Trigger on workspace state changes
  triggers = {
    workspace_transition = data.coder_workspace.me.transition
    vm_id               = proxmox_vm_qemu.workspace[0].vmid
    node                = data.coder_parameter.proxmox_node.value
  }
  
  # Start VM on workspace start
  provisioner "local-exec" {
    when    = create
    command = data.coder_workspace.me.transition == "start" ? "echo 'VM should be started'" : "echo 'VM created'"
  }
  
  # Note: Actual VM power management would require additional tooling
  # This is a placeholder for proper power management implementation
  
  depends_on = [proxmox_vm_qemu.workspace]
}

# Metadata for workspace information
resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = proxmox_vm_qemu.workspace[0].id

  item {
    key   = "node"
    value = data.coder_parameter.proxmox_node.value
  }
  item {
    key   = "vm_id" 
    value = proxmox_vm_qemu.workspace[0].vmid
  }
  item {
    key   = "cores"
    value = data.coder_parameter.cpu_cores.value
  }
  item {
    key   = "memory"
    value = "${data.coder_parameter.memory.value} MB"
  }
  item {
    key   = "disk_size"
    value = "${data.coder_parameter.disk_size.value} GB"
  }
  item {
    key   = "template"
    value = var.vm_template
  }
  item {
    key   = "ip_address"
    value = proxmox_vm_qemu.workspace[0].default_ipv4_address
  }
}