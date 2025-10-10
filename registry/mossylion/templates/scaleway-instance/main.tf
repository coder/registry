
terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2"
    }
    scaleway = {
      source  = "scaleway/scaleway"
      version = "~> 2"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = "~> 2"
    }
  }
  required_version = ">= 1.0"
}

provider "scaleway" {
  access_key = var.access_key
  secret_key = var.secret_key
  region     = data.coder_parameter.region.value
}

locals {
  hostname   = lower(data.coder_workspace.me.name)
  linux_user = "coder"
}

data "cloudinit_config" "user_data" {
  gzip          = false
  base64_encode = false

  boundary = "//"

  part {
    filename     = "cloud-config.yaml"
    content_type = "text/cloud-config"

    content = templatefile("${path.module}/cloud-init/cloud-config.yaml.tftpl", {
      hostname   = local.hostname
      linux_user = local.linux_user
    })
  }

  part {
    filename     = "userdata.sh"
    content_type = "text/x-shellscript"

    content = templatefile("${path.module}/cloud-init/userdata.sh.tftpl", {
      linux_user        = local.linux_user
      init_script       = coder_agent.main.init_script
      coder_agent_token = coder_agent.main.token
    })
  }
}
data "coder_provisioner" "me" {}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = data.coder_provisioner.me.os
  auth = "token"

  startup_script = <<-EOT
    set -e

    # Install additional tools or run commands at workspace startup
    # Uncomment and customize as needed:
    # sudo apt-get update
    # sudo apt-get install -y build-essential
  EOT

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
    display_name = "Disk Usage"
    key          = "1_disk_usage"
    script       = "coder stat disk --path /home/${local.linux_user}"
    interval     = 600
    timeout      = 30
  }
}

module "code-server" {
  source   = "registry.coder.com/modules/code-server/coder"
  version  = "1.3.1"
  agent_id = coder_agent.main.id
  order    = 1
  folder   = "/home/${local.linux_user}"
}

# Runs a script at workspace start/stop or on a cron schedule
# details: https://registry.terraform.io/providers/coder/coder/latest/docs/resources/script

module "dotfiles" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dotfiles/coder"
  version  = "1.2.1"
  agent_id = coder_agent.main.id
}

resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = scaleway_instance_server.workspace[0].id

  item {
    key   = "region"
    value = data.coder_parameter.region.value
  }
  item {
    key   = "instance type"
    value = scaleway_instance_server.workspace[0].type
  }
  item {
    key   = "image"
    value = data.coder_parameter.base_image.value
  }
}

resource "coder_metadata" "volume_info" {
  resource_id = scaleway_block_volume.persistent_storage.id

  item {
    key   = "size"
    value = "${scaleway_block_volume.persistent_storage.size_in_gb} GiB"
  }
  item {
    key   = "iops"
    value = scaleway_block_volume.persistent_storage.iops
  }
}

data "coder_parameter" "region" {
  name        = "Scaleway Region"
  description = "Region to deploy server into"
  type        = "string"
  default     = "fr-par"
  option {
    name  = "France - Paris (fr-par)"
    value = "fr-par"
    icon  = "/emojis/1f1eb-1f1f7.png"
  }
  option {
    name  = "Netherlands -  Amsterdam (nl-ams)"
    value = "nl-ams"
    icon  = "/emojis/1f1f3-1f1f1.png"
  }
  option {
    name  = "Poland - Warsaw (pl-waw)"
    value = "pl-waw"
    icon  = "/emojis/1f1f5-1f1f1.png"
  }
}

data "coder_parameter" "base_image" {
  name        = "Image"
  description = "Which base image would you like to use?"
  type        = "string"
  form_type   = "radio"
  default     = "debian_trixie"

  option {
    name  = "Debian 13 (Trixie)"
    value = "debian_trixie"
    icon  = "/icon/debian.svg"
  }

  option {
    name  = "Debian 12 (Bookworm)"
    value = "debian_bookworm"
    icon  = "/icon/debian.svg"
  }

  option {
    name  = "Ubuntu 24.04 (Noble)"
    value = "ubuntu_noble"
    icon  = "/icon/ubuntu.svg"
  }

  option {
    name  = "Fedora 41"
    value = "fedora_41"
    icon  = "/icon/fedora.svg"
  }
}

data "coder_parameter" "disk_size" {
  name      = "Disk Size"
  type      = "number"
  form_type = "slider"
  default   = "10"
  order     = 8
  validation {
    min       = 10
    max       = 500
    monotonic = "increasing"
  }
}

locals {
  scaleway_config_raw = jsondecode(file("${path.module}/scaleway-config.json"))

  scaleway_instance_options = {
    for instance in local.scaleway_config_raw :
    instance.name => {
      name  = "${instance.name} (${instance.cpu} CPU, ${instance.gpu} GPU, ${floor(instance.ram / 1073741824)} GB RAM)"
      value = instance.name
    }
  }
}

data "coder_parameter" "instance_size" {
  name         = "instance_size"
  display_name = "Instance Size"
  description  = "Which Instance Size should be used?"
  default      = "STARDUST1-S"
  type         = "string"
  icon         = "/icon/memory.svg"
  mutable      = false
  form_type    = "dropdown"

  dynamic "option" {
    for_each = local.scaleway_instance_options
    content {
      name  = option.value.name
      value = option.value.value
    }
  }
}

data "coder_parameter" "volume_iops" {
  name        = "Volume IOPS"
  description = "IOPS to provision for disk"
  type        = "number"
  default     = 5000
  option {
    name  = "5000"
    value = 5000
  }
  option {
    name  = "15000"
    value = 15000
  }
}

resource "scaleway_instance_server" "workspace" {
  count      = data.coder_workspace.me.start_count
  name       = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
  type       = data.coder_parameter.instance_size.value
  image      = data.coder_parameter.base_image.value
  ip_ids     = [scaleway_instance_ip.server_ip[0].id, scaleway_instance_ip.v4_server_ip[0].id]
  project_id = var.project_id
  user_data = {
    cloud-init = data.cloudinit_config.user_data.rendered
  }
  additional_volume_ids = [scaleway_block_volume.persistent_storage.id]
}

resource "scaleway_block_volume" "persistent_storage" {
  iops       = data.coder_parameter.volume_iops.value
  name       = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}-home"
  size_in_gb = data.coder_parameter.disk_size.value
  project_id = var.project_id
}


resource "scaleway_instance_ip" "server_ip" {
  count      = data.coder_workspace.me.start_count
  type       = "routed_ipv6"
  project_id = var.project_id
}

resource "scaleway_instance_ip" "v4_server_ip" {
  count      = data.coder_workspace.me.start_count
  type       = "routed_ipv4"
  project_id = var.project_id
}

variable "project_id" {
  type        = string
  description = "ID of the project to deploy into"
}

variable "access_key" {
  type        = string
  description = "Access key to use to deploy"
}

variable "secret_key" {
  type        = string
  description = "Secret key to use to deploy"
}
