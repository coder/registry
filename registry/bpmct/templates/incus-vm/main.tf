terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.4.0"
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

module "portabledesktop" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/portabledesktop/coder"
  version  = "~> 0.1"
  agent_id = coder_agent.main[0].id
}

provider "incus" {}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_parameter" "host" {
  name         = "host"
  display_name = "Host"
  description  = "Select the host to run this workspace on. **ThinkStation** is an amd64 desktop machine. **CoderPi** is an arm64 Raspberry Pi."
  type         = "string"
  default      = "ThinkStation"
  mutable      = false
  order        = 1

  option {
    name  = "ThinkStation"
    value = "ThinkStation"
    icon  = "/icon/desktop.svg"
  }

  option {
    name  = "CoderPi"
    value = "CoderPi"
    icon  = "/icon/memory.svg"
  }
}

data "coder_parameter" "image" {
  name         = "image"
  display_name = "Image"
  description  = "The image to use. Ubuntu images use cloud-init. NixOS images are provisioned via incus exec + nixos-rebuild."
  default      = "ubuntu/jammy/cloud"
  icon         = "/icon/image.svg"
  mutable      = true

  option {
    name  = "Ubuntu 22.04 LTS (Jammy)"
    value = "ubuntu/jammy/cloud"
    icon  = "/icon/ubuntu.svg"
  }

  option {
    name  = "Ubuntu 24.04 LTS (Noble)"
    value = "ubuntu/noble/cloud"
    icon  = "/icon/ubuntu.svg"
  }

  option {
    name  = "NixOS 25.11"
    value = "nixos/25.11"
    icon  = "/icon/nix.svg"
  }

  option {
    name  = "NixOS Unstable"
    value = "nixos/unstable"
    icon  = "/icon/nix.svg"
  }
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "Number of CPUs to allocate."
  type         = "number"
  form_type    = "dropdown"
  default      = 2
  icon         = "https://raw.githubusercontent.com/matifali/logos/main/cpu-3.svg"
  mutable      = true
  order        = 2

  dynamic "option" {
    for_each = data.coder_parameter.host.value == "ThinkStation" ? [1, 2, 4, 6, 8, 12] : [0.5, 1, 1.5, 2]
    content {
      name  = tostring(option.value)
      value = option.value
    }
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory (GB)"
  description  = "Amount of memory in GB."
  type         = "number"
  form_type    = "slider"
  default      = 4
  icon         = "/icon/memory.svg"
  mutable      = true
  order        = 3
  validation {
    min = 1
    max = data.coder_parameter.host.value == "ThinkStation" ? 24 : 12
  }
}

data "coder_parameter" "usb_passthrough" {
  name         = "usb_passthrough"
  display_name = "USB Passthrough"
  description  = "Pass a USB device through to the VM. Only applicable when host is ThinkStation."
  type         = "string"
  form_type    = "dropdown"
  default      = "none"
  mutable      = true
  order        = 4

  option {
    name  = "None"
    value = "none"
  }

  option {
    name  = "Kindle Paperwhite (1949:0004)"
    value = "kindle"
  }

  option {
    name  = "Nook Simple Touch (2080:0003)"
    value = "nook"
  }

  option {
    name  = "Kindle Fire 1st Gen (1949:0006)"
    value = "kindle_fire"
  }
}

data "coder_parameter" "snapshot_on_stop" {
  name         = "snapshot_on_stop"
  display_name = "Snapshot on stop"
  description  = "Take a snapshot of the VM when the workspace stops."
  type         = "bool"
  form_type    = "checkbox"
  default      = false
  mutable      = true
  ephemeral    = true
  order        = 5
}

data "coder_parameter" "snapshot_name" {
  count        = data.coder_parameter.snapshot_on_stop.value == "true" ? 1 : 0
  name         = "snapshot_name"
  display_name = "Snapshot name"
  description  = "Name for the snapshot."
  type         = "string"
  default      = "snap-${formatdate("YYYYMMDD-hhmmss", timestamp())}"
  mutable      = true
  ephemeral    = true
  order        = 6
}

resource "coder_agent" "main" {
  count = data.coder_workspace.me.start_count
  arch  = data.coder_parameter.host.value == "ThinkStation" ? "amd64" : "arm64"
  os    = "linux"
  dir   = "/home/${local.workspace_user}"

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
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path /home/${local.workspace_user}"
    interval     = 60
    timeout      = 1
  }
}

resource "incus_image" "image" {
  remote = local.incus_remote
  source_image = {
    remote = "images"
    name   = local.is_nixos ? data.coder_parameter.image.value : "${data.coder_parameter.image.value}/${data.coder_parameter.host.value == "ThinkStation" ? "amd64" : "arm64"}"
    type         = "virtual-machine"
    architecture = data.coder_parameter.host.value == "ThinkStation" ? "x86_64" : "aarch64"
  }
}

resource "incus_instance" "dev" {
  remote  = local.incus_remote
  running = data.coder_workspace.me.start_count == 1
  name    = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
  image   = incus_image.image.fingerprint
  type     = "virtual-machine"
  profiles = local.is_nixos && data.coder_parameter.host.value == "ThinkStation" ? ["default", "nix-shared"] : ["default"]

  dynamic "device" {
    for_each = local.usb_device != null ? [local.usb_device] : []
    content {
      name = device.value.name
      type = "usb"
      properties = {
        vendorid  = device.value.vendorid
        productid = device.value.productid
      }
    }
  }

  lifecycle {
    ignore_changes = [
      config["cloud-init.user-data"],
      config["user.coder-agent-token"],
      config["raw.qemu.conf"],
      image,
    ]
  }

  config = merge(
    {
      "limits.cpu"    = tostring(local.cpu)
      "limits.memory" = "${local.memory}GiB"
      "raw.qemu.conf" = <<-QEMUCONF
        [device "qemu_balloon"]
        driver = "virtio-balloon-pci"
        bus = "qemu_pcie0"
        addr = "00.0"
        multifunction = "on"
        free-page-reporting = "on"
      QEMUCONF
      "security.secureboot"    = false
      "boot.autostart"         = data.coder_workspace.me.start_count == 1
      "user.coder-agent-token" = local.agent_token
    },
    local.is_nixos ? {} : {
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

runcmd:
  - apt-get update -qq && apt-get install -y curl adb
  - chown -R ${local.workspace_user}:${local.workspace_user} /home/${local.workspace_user}
  - |
    if [ ! -s /opt/coder/init ]; then
      curl -fsSL '${data.coder_workspace.me.access_url}/bin/coder-linux-amd64' -o /opt/coder/coder-agent-bin
      chmod +x /opt/coder/coder-agent-bin
      printf '#!/bin/bash\nsource /opt/coder/init.env\nexec /opt/coder/coder-agent-bin agent\n' > /opt/coder/init
      chmod +x /opt/coder/init
    fi
  - systemctl enable --now coder-agent.service
EOF
    }
  )
}

# Token refresh for Ubuntu/cloud-init VMs
resource "null_resource" "token_refresh" {
  count = data.coder_workspace.me.start_count == 1 && !local.is_nixos ? 1 : 0

  triggers = {
    agent_token = local.agent_token
    instance    = incus_instance.dev.name
  }

  depends_on = [incus_instance.dev]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for VM agent to be ready..."
      for i in $(seq 1 30); do
        if incus exec ${local.incus_remote}:${incus_instance.dev.name} -- true 2>/dev/null; then
          break
        fi
        echo "Attempt $i: VM agent not ready yet, waiting..."
        sleep 5
      done
      echo "Waiting for cloud-init to complete..."
      incus exec ${local.incus_remote}:${incus_instance.dev.name} -- bash -c '
        for i in $(seq 1 60); do
          if [ -f /var/lib/cloud/instance/boot-finished ]; then
            break
          fi
          sleep 5
        done
      '
      echo "Updating Coder agent token..."
      incus config set ${local.incus_remote}:${incus_instance.dev.name} user.coder-agent-token ${local.agent_token}
      incus exec ${local.incus_remote}:${incus_instance.dev.name} -- bash -c '
        printf "CODER_AGENT_TOKEN=${local.agent_token}\nCODER_AGENT_URL=${data.coder_workspace.me.access_url}\n" > /opt/coder/init.env
        chown root:root /opt/coder/init.env
        chmod 600 /opt/coder/init.env
        systemctl restart coder-agent
      '
    EOT
  }
}

resource "incus_instance_snapshot" "on_stop" {
  count    = data.coder_parameter.snapshot_on_stop.value == "true" ? 1 : 0
  remote   = local.incus_remote
  instance = incus_instance.dev.name
  name     = try(data.coder_parameter.snapshot_name[0].value, "snap")
  stateful = false
  lifecycle {
    ignore_changes = all
  }
}

locals {
  incus_remote      = data.coder_parameter.host.value == "ThinkStation" ? "thinkstation" : "local"
  workspace_user    = lower(data.coder_workspace_owner.me.name)
  cpu               = data.coder_parameter.cpu.value
  memory            = data.coder_parameter.memory.value
  agent_id          = data.coder_workspace.me.start_count == 1 ? coder_agent.main[0].id : ""
  agent_token       = data.coder_workspace.me.start_count == 1 ? coder_agent.main[0].token : ""
  agent_init_script = data.coder_workspace.me.start_count == 1 ? coder_agent.main[0].init_script : ""

  # USB device map — add more entries here as needed
  usb_devices = {
    kindle      = { name = "kindle", vendorid = "1949", productid = "0004" }
    nook        = { name = "nook", vendorid = "2080", productid = "0003" }
    kindle_fire = { name = "kindle_fire", vendorid = "1949", productid = "0006" }
  }

  usb_passthrough_value = data.coder_parameter.usb_passthrough.value
  usb_device = (
    local.usb_passthrough_value != "none" &&
    data.coder_parameter.host.value == "ThinkStation" &&
    contains(keys(local.usb_devices), local.usb_passthrough_value)
  ) ? local.usb_devices[local.usb_passthrough_value] : null
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
    value = "images:${data.coder_parameter.image.value}"
  }
  item {
    key   = "cpus"
    value = tostring(local.cpu)
  }
  item {
    key   = "memory"
    value = tostring(local.memory)
  }
}
