terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.78.0"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

provider "coder" {}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
  insecure  = true

  ssh {
    username    = "terraform"
    private_key = var.proxmox_ssh_private_key

    node {
      name    = "pve01"
      address = "10.200.0.36"
    }
    node {
      name    = "pve02"
      address = "10.200.0.37"
    }
    node {
      name    = "pve03"
      address = "10.200.0.38"
    }
  }
}

# =============================================================================
# Template variables (set during coder templates push)
# =============================================================================

variable "proxmox_api_url" {
  type = string
}

variable "proxmox_token_id" {
  type      = string
  sensitive = true
}

variable "proxmox_token_secret" {
  type      = string
  sensitive = true
}

variable "proxmox_ssh_private_key" {
  type      = string
  sensitive = true
}

# =============================================================================
# Coder data sources
# =============================================================================

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# =============================================================================
# Workspace parameters
# =============================================================================

data "coder_parameter" "node" {
  name         = "node"
  display_name = "Proxmox Node"
  type         = "string"
  default      = "pve01"
  mutable      = false
  order        = 1
  option {
    name  = "pve01"
    value = "pve01"
  }
  option {
    name  = "pve02"
    value = "pve02"
  }
  option {
    name  = "pve03"
    value = "pve03"
  }
}

data "coder_parameter" "cpu_cores" {
  name         = "cpu_cores"
  display_name = "CPU Cores"
  type         = "number"
  default      = 4
  mutable      = true
  order        = 2
}

data "coder_parameter" "memory_mb" {
  name         = "memory_mb"
  display_name = "Memory (MB)"
  type         = "number"
  default      = 8192
  mutable      = true
  order        = 3
}

data "coder_parameter" "disk_size_gb" {
  name         = "disk_size_gb"
  display_name = "Disk Size (GB)"
  type         = "number"
  default      = 32
  mutable      = true
  order        = 4
  validation {
    min       = 10
    max       = 100
    monotonic = "increasing"
  }
}

data "coder_parameter" "git_url" {
  name         = "git_url"
  display_name = "Git Repository URL"
  type         = "string"
  default      = ""
  description  = "HTTPS clone URL. Leave blank to skip cloning."
  mutable      = false
  order        = 10
}

data "coder_parameter" "git_branch" {
  name         = "git_branch"
  display_name = "Git Branch"
  type         = "string"
  default      = ""
  description  = "Branch to clone. Leave blank for the default branch."
  mutable      = false
  order        = 11
}

data "coder_parameter" "git_folder_name" {
  name         = "git_folder_name"
  display_name = "Folder Name"
  type         = "string"
  default      = ""
  description  = "Destination folder name. Leave blank to use the repository name."
  mutable      = false
  order        = 12
}

data "coder_parameter" "git_base_dir" {
  name         = "git_base_dir"
  display_name = "Base Directory"
  type         = "string"
  default      = ""
  description  = "Parent directory for the clone. Defaults to $HOME."
  mutable      = false
  order        = 13
}

data "coder_parameter" "git_depth" {
  name         = "git_depth"
  display_name = "Clone Depth"
  type         = "number"
  default      = 0
  description  = "Shallow clone depth. 0 for full clone."
  mutable      = false
  order        = 14
}

data "coder_parameter" "install_docker" {
  name         = "install_docker"
  display_name = "Docker & Compose"
  type         = "bool"
  default      = "false"
  description  = "Install Docker Engine and Docker Compose. The coder user is added to the docker group."
  mutable      = false
  order        = 5
}

# =============================================================================
# Locals
# =============================================================================

locals {
  hostname    = lower(data.coder_workspace.me.name)
  vm_name     = "coder-${lower(data.coder_workspace_owner.me.name)}-${local.hostname}"
  repo_name   = data.coder_parameter.git_url.value != "" ? (data.coder_parameter.git_folder_name.value != "" ? data.coder_parameter.git_folder_name.value : replace(element(split("/", data.coder_parameter.git_url.value), length(split("/", data.coder_parameter.git_url.value)) - 1), ".git", "")) : ""
  git_base    = data.coder_parameter.git_base_dir.value != "" ? data.coder_parameter.git_base_dir.value : "/home/coder"
  workdir     = local.repo_name != "" ? "${local.git_base}/${local.repo_name}" : "/home/coder"
}

# =============================================================================
# Coder agent
# =============================================================================

resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"
  dir  = local.workdir

  startup_script_behavior = "non-blocking"

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

# =============================================================================
# Cloud-init snippet (OS-level setup only)
# =============================================================================

resource "proxmox_virtual_environment_file" "cloud_init" {
  content_type = "snippets"
  datastore_id = "ceph-pve"
  node_name    = data.coder_parameter.node.value

  source_raw {
    data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
      hostname              = local.vm_name
      coder_agent_token     = coder_agent.main.token
      coder_init_script_b64 = base64encode(coder_agent.main.init_script)
      install_docker        = data.coder_parameter.install_docker.value
    })
    file_name = "${local.vm_name}.yaml"
  }
}

# =============================================================================
# Proxmox VM (persists across stop/start, destroyed on workspace delete)
# =============================================================================

resource "proxmox_virtual_environment_vm" "agent" {
  name      = local.vm_name
  node_name = data.coder_parameter.node.value
  pool_id   = "coder"

  clone {
    node_name = "pve01"
    vm_id     = 101
    full      = true
    retries   = 5
  }

  cpu {
    cores   = data.coder_parameter.cpu_cores.value
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = data.coder_parameter.memory_mb.value
  }

  agent {
    enabled = true
  }

  scsi_hardware = "virtio-scsi-pci"
  boot_order    = ["scsi0", "ide2"]

  disk {
    interface    = "scsi0"
    datastore_id = "local-lvm"
    size         = data.coder_parameter.disk_size_gb.value
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge = "vmbrDMZ"
    model  = "virtio"
  }

  vga {
    type = "serial0"
  }

  serial_device {
    device = "socket"
  }

  initialization {
    type         = "nocloud"
    datastore_id = "local-lvm"

    user_data_file_id = proxmox_virtual_environment_file.cloud_init.id

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  tags = ["coder", "workspace", local.vm_name]

  on_boot = true
  started = data.coder_workspace.me.start_count > 0

  lifecycle {
    ignore_changes = [
      disk[0].size,
    ]
  }

  depends_on = [proxmox_virtual_environment_file.cloud_init]
}

# =============================================================================
# Modules — Workspace utilities
# =============================================================================

module "coder-login" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.1.1"
  agent_id = coder_agent.main.id
}

module "git-config" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-config/coder"
  version  = "1.0.33"
  agent_id = coder_agent.main.id
}

module "git-commit-signing" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-commit-signing/coder"
  version  = "1.0.32"
  agent_id = coder_agent.main.id
}

module "dotfiles" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dotfiles/coder"
  version  = "1.4.1"
  agent_id = coder_agent.main.id
}

module "personalize" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/personalize/coder"
  version  = "1.0.32"
  agent_id = coder_agent.main.id
}

# =============================================================================
# Modules — Git
# =============================================================================

module "git-clone" {
  count       = data.coder_parameter.git_url.value != "" ? data.coder_workspace.me.start_count : 0
  source      = "registry.coder.com/coder/git-clone/coder"
  version     = "1.2.3"
  agent_id    = coder_agent.main.id
  url         = data.coder_parameter.git_url.value
  base_dir    = data.coder_parameter.git_base_dir.value != "" ? data.coder_parameter.git_base_dir.value : null
  branch_name = data.coder_parameter.git_branch.value != "" ? data.coder_parameter.git_branch.value : null
  folder_name = data.coder_parameter.git_folder_name.value != "" ? data.coder_parameter.git_folder_name.value : null
  depth       = data.coder_parameter.git_depth.value
}

# =============================================================================
# Modules — IDEs and file access
# =============================================================================

module "code-server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "1.4.4"
  agent_id = coder_agent.main.id
  folder   = local.workdir
}

module "cursor" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/cursor/coder"
  version  = "1.4.1"
  agent_id = coder_agent.main.id
  folder   = local.workdir
}

module "filebrowser" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/filebrowser/coder"
  version  = "1.1.4"
  agent_id = coder_agent.main.id
}

# =============================================================================
# Modules — Coding Agents (all installed, configure at runtime)
# =============================================================================

module "claude-code" {
  count           = data.coder_workspace.me.start_count
  source          = "git::https://github.com/stl314159/coder-registry.git//registry/coder/modules/claude-code?ref=main"
  agent_id        = coder_agent.main.id
  workdir         = local.workdir
  permission_mode = "bypassPermissions"
}

resource "random_integer" "codex_port" {
  min = 3300
  max = 3399
}

module "codex" {
  count         = data.coder_workspace.me.start_count
  source        = "git::https://github.com/stl314159/coder-registry.git//registry/coder-labs/modules/codex?ref=main"
  agent_id      = coder_agent.main.id
  workdir       = local.workdir
  agentapi_port = random_integer.codex_port.result
}

resource "random_integer" "opencode_port" {
  min = 3400
  max = 3499
}

module "opencode" {
  count         = data.coder_workspace.me.start_count
  source        = "git::https://github.com/stl314159/coder-registry.git//registry/coder-labs/modules/opencode?ref=main"
  agent_id      = coder_agent.main.id
  workdir       = local.workdir
  agentapi_port = random_integer.opencode_port.result
}
