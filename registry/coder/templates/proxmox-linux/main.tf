terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

# Keep all your original coder_parameter blocks
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
  default      = "9000"
  mutable      = false

  option {
    name  = "Ubuntu 22.04 LTS"
    value = "9000"
    icon  = "/icon/ubuntu.svg"
  }

  option {
    name  = "Ubuntu 20.04 LTS"
    value = "9001"
    icon  = "/icon/ubuntu.svg"
  }

  option {
    name  = "Debian 12"
    value = "9002"
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
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Mock VM resource for testing UI
resource "coder_agent" "main" {
  count          = data.coder_workspace.me.start_count
  arch           = "amd64"
  os             = "linux"
  startup_script = <<-EOT
    #!/bin/bash
    echo "🚀 Mock Proxmox workspace started!"
    echo "Node: ${data.coder_parameter.proxmox_node.value}"
    echo "Template: ${data.coder_parameter.vm_template.value}"
    echo "CPU: ${data.coder_parameter.cpu_cores.value} cores"
    echo "Memory: ${data.coder_parameter.memory_mb.value} MB"
  EOT

  metadata {
    key          = "cpu"
    display_name = "CPU Usage"
    interval     = 5
    timeout      = 5
    script       = "echo '25%'"
  }

  metadata {
    key          = "memory"
    display_name = "Memory Usage"
    interval     = 5
    timeout      = 5
    script       = "echo '1.2GB / ${data.coder_parameter.memory_mb.value}MB'"
  }
}

# Mock Proxmox VM - shows in logs what would be created
resource "null_resource" "mock_proxmox_vm" {
  count = data.coder_workspace.me.start_count

  provisioner "local-exec" {
    command = <<-EOT
      echo "🖥️  Mock Proxmox VM Configuration:"
      echo "   Node: ${data.coder_parameter.proxmox_node.value}"
      echo "   Template ID: ${data.coder_parameter.vm_template.value}"
      echo "   CPU: ${data.coder_parameter.cpu_cores.value} cores"
      echo "   Memory: ${data.coder_parameter.memory_mb.value} MB"
      echo "   VM Name: coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
    EOT
  }
}

module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/modules/code-server/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main[0].id
  order    = 1
}

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = null_resource.mock_proxmox_vm[0].id

  item {
    key   = "proxmox_node"
    value = data.coder_parameter.proxmox_node.value
  }

  item {
    key   = "vm_template"
    value = data.coder_parameter.vm_template.value
  }

  item {
    key   = "cpu_cores"
    value = data.coder_parameter.cpu_cores.value
  }

  item {
    key   = "memory"
    value = "${data.coder_parameter.memory_mb.value} MB"
  }
}
