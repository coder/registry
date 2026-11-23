terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
    incus = {
      source  = "lxc/incus"
      version = "~> 1.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "incus" {}

variable "arch" {
  description = "CPU architecture of the VM host. Set this when pushing the template to match your Incus host. Valid values: amd64, arm64."
  type        = string
  default     = "amd64"
  validation {
    condition     = contains(["amd64", "arm64"], var.arch)
    error_message = "arch must be amd64 or arm64."
  }
}

variable "storage_pool" {
  description = "Incus storage pool for the root disk. Run `incus storage list` on the host to see available pools."
  type        = string
  default     = "default"
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_parameter" "image" {
  name         = "image"
  display_name = "Image"
  description  = "Linux images come from images.linuxcontainers.org. Windows uses a golden image that you build on the Incus host."
  type         = "string"
  default      = "ubuntu/noble/cloud"
  icon         = "/icon/image.svg"
  mutable      = false
  order        = 1

  option {
    name  = "Ubuntu 24.04 LTS (Noble)"
    value = "ubuntu/noble/cloud"
    icon  = "/icon/ubuntu.svg"
  }

  option {
    name  = "Ubuntu 22.04 LTS (Jammy)"
    value = "ubuntu/jammy/cloud"
    icon  = "/icon/ubuntu.svg"
  }

  option {
    name  = "Debian 12 (Bookworm)"
    value = "debian/12/cloud"
    icon  = "/icon/debian.svg"
  }

  option {
    name  = "Windows Server 2022"
    value = "windows"
    icon  = "/icon/windows.svg"
  }
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "Number of vCPUs."
  type         = "number"
  default      = 2
  icon         = "https://raw.githubusercontent.com/matifali/logos/main/cpu-3.svg"
  mutable      = true
  order        = 2
  validation {
    min = 1
    max = 16
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (GB)"
  type         = "number"
  default      = 4
  icon         = "/icon/memory.svg"
  mutable      = true
  order        = 3
  validation {
    min = 1
    max = 64
  }
}

data "coder_parameter" "disk" {
  name         = "disk"
  display_name = "Disk (GB)"
  type         = "number"
  default      = 30
  icon         = "/icon/database.svg"
  mutable      = true
  order        = 4
  validation {
    min = 10
    max = 500
  }
}

resource "coder_agent" "main" {
  count = data.coder_workspace.me.start_count
  arch  = var.arch
  os    = local.is_windows ? "windows" : "linux"
  dir   = local.is_windows ? "C:/coder" : null

  # Windows boots, then downloads the agent binary.
  connection_timeout = local.is_windows ? 600 : 120

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Disk"
    key          = "2_disk"
    script       = local.is_windows ? "coder stat disk --path C:/" : "coder stat disk --path /"
    interval     = 60
    timeout      = 1
  }
}

module "code-server" {
  count    = data.coder_workspace.me.start_count == 1 && !local.is_windows ? 1 : 0
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main[0].id
}

resource "incus_image" "image" {
  count = local.is_windows ? 0 : 1
  source_image = {
    remote       = "images"
    name         = "${data.coder_parameter.image.value}/${var.arch}"
    type         = "virtual-machine"
    architecture = var.arch == "amd64" ? "x86_64" : "aarch64"
  }
}

resource "incus_instance" "dev" {
  # The provider never starts a Windows VM. null_resource.windows_stop stops
  # it, and null_resource.windows_seed attaches the token ISO and starts it.
  running = local.is_windows ? false : data.coder_workspace.me.start_count == 1
  name    = local.instance_name
  image   = local.is_windows ? var.windows_image : incus_image.image[0].fingerprint
  type    = "virtual-machine"

  depends_on = [null_resource.windows_seed_volume, null_resource.windows_stop]

  config = merge(
    {
      "limits.cpu"             = tostring(data.coder_parameter.cpu.value)
      "limits.memory"          = "${data.coder_parameter.memory.value}GiB"
      "security.secureboot"    = false
      "boot.autostart"         = data.coder_workspace.me.start_count == 1
      "user.coder-agent-token" = local.agent_token
    },
    local.is_windows ? {
      # The golden image installs in legacy BIOS mode. On Incus 6.0 with
      # QEMU 8.2, UEFI could not read the install disk and the default
      # Hyper-V CPU flags stopped the Windows boot.
      "security.csm" = true
      "raw.qemu"     = "-cpu host"
      } : {
      "cloud-init.user-data" = <<-EOF
        #cloud-config
        hostname: ${lower(data.coder_workspace.me.name)}
        users:
          - name: ${local.workspace_user}
            uid: 1000
            groups: sudo
            shell: /bin/bash
            sudo: ALL=(ALL) NOPASSWD:ALL
        write_files:
          - path: /opt/coder/init
            permissions: "0755"
            encoding: b64
            content: ${base64encode(local.agent_init_script)}
          - path: /opt/coder/init.env
            permissions: "0600"
            content: |
              CODER_AGENT_TOKEN=${local.agent_token}
              CODER_AGENT_URL=${data.coder_workspace.me.access_url}
          - path: /etc/systemd/system/coder-agent.service
            permissions: "0644"
            content: |
              [Unit]
              Description=Coder Agent
              After=network-online.target
              Wants=network-online.target
              [Service]
              User=${local.workspace_user}
              EnvironmentFile=/opt/coder/init.env
              ExecStart=/opt/coder/init
              Restart=always
              RestartSec=10
              TimeoutStopSec=90
              KillMode=process
              OOMScoreAdjust=-900
              SyslogIdentifier=coder-agent
              [Install]
              WantedBy=multi-user.target
        runcmd:
          - systemctl enable --now coder-agent.service
      EOF
    }
  )

  device {
    name = "root"
    type = "disk"
    properties = {
      path = "/"
      pool = var.storage_pool
      size = "${local.disk_size}GiB"
    }
  }

  lifecycle {
    precondition {
      condition     = !local.is_windows || var.arch == "amd64"
      error_message = "The Windows image needs an amd64 Incus host."
    }
    ignore_changes = [
      config["cloud-init.user-data"],
      config["user.coder-agent-token"],
      image,
    ]
  }
}

resource "null_resource" "token_refresh" {
  count = data.coder_workspace.me.start_count == 1 && !local.is_windows ? 1 : 0

  triggers = {
    agent_token = local.agent_token
    instance    = incus_instance.dev.name
  }

  depends_on = [incus_instance.dev]

  provisioner "local-exec" {
    command = <<-EOT
      INSTANCE="${incus_instance.dev.name}"
      echo "Waiting for VM agent..."
      for i in $(seq 1 40); do
        incus exec "$INSTANCE" -- true 2>/dev/null && break
        echo "Attempt $i: not ready, waiting..."
        sleep 5
      done
      echo "Waiting for cloud-init..."
      incus exec "$INSTANCE" -- bash -c '
        for i in $(seq 1 60); do
          [ -f /var/lib/cloud/instance/boot-finished ] && break
          sleep 5
        done
      '
      echo "Refreshing agent token..."
      printf 'CODER_AGENT_TOKEN=${local.agent_token}\nCODER_AGENT_URL=${data.coder_workspace.me.access_url}\n' \
        | incus exec "$INSTANCE" -- bash -c 'cat > /opt/coder/init.env && chmod 600 /opt/coder/init.env'
      incus exec "$INSTANCE" -- systemctl restart coder-agent.service
    EOT
  }
}

resource "coder_metadata" "info" {
  count       = data.coder_workspace.me.start_count
  resource_id = incus_instance.dev.name

  item {
    key   = "instance"
    value = incus_instance.dev.name
  }
  item {
    key   = "image"
    value = local.is_windows ? var.windows_image : "images:${data.coder_parameter.image.value}/${var.arch}"
  }
  item {
    key   = "storage_pool"
    value = var.storage_pool
  }
  item {
    key   = "arch"
    value = var.arch
  }
  item {
    key   = "cpu"
    value = tostring(data.coder_parameter.cpu.value)
  }
  item {
    key   = "memory"
    value = "${data.coder_parameter.memory.value} GiB"
  }
  item {
    key   = "disk"
    value = "${local.disk_size} GiB"
  }
}

locals {
  workspace_user = lower(data.coder_workspace_owner.me.name)
  instance_name  = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
  seed_volume    = "coder-init-${local.instance_name}"
  is_windows     = data.coder_parameter.image.value == "windows"
  # The Windows golden image has a 60 GiB partition. Incus cannot shrink a root disk.
  disk_size         = local.is_windows ? max(data.coder_parameter.disk.value, 60) : data.coder_parameter.disk.value
  agent_token       = data.coder_workspace.me.start_count == 1 ? coder_agent.main[0].token : ""
  agent_init_script = data.coder_workspace.me.start_count == 1 ? coder_agent.main[0].init_script : ""
}
