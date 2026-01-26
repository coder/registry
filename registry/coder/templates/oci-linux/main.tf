terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    oci = {
      source = "oracle/oci"
    }
    cloudinit = {
      source = "hashicorp/cloudinit"
    }
  }
}

# OCI Region parameter
data "coder_parameter" "region" {
  name         = "region"
  display_name = "Region"
  description  = "The OCI region to deploy the workspace in."
  default      = "us-ashburn-1"
  mutable      = false
  option {
    name  = "US East (Ashburn)"
    value = "us-ashburn-1"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "US West (Phoenix)"
    value = "us-phoenix-1"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "US West (San Jose)"
    value = "us-sanjose-1"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "Canada Southeast (Montreal)"
    value = "ca-montreal-1"
    icon  = "/emojis/1f1e8-1f1e6.png"
  }
  option {
    name  = "Canada Southeast (Toronto)"
    value = "ca-toronto-1"
    icon  = "/emojis/1f1e8-1f1e6.png"
  }
  option {
    name  = "South America East (Sao Paulo)"
    value = "sa-saopaulo-1"
    icon  = "/emojis/1f1e7-1f1f7.png"
  }
  option {
    name  = "South America West (Santiago)"
    value = "sa-santiago-1"
    icon  = "/emojis/1f1e8-1f1f1.png"
  }
  option {
    name  = "South America West (Vinhedo)"
    value = "sa-vinhedo-1"
    icon  = "/emojis/1f1e7-1f1f7.png"
  }
  option {
    name  = "UK South (London)"
    value = "uk-london-1"
    icon  = "/emojis/1f1ec-1f1e7.png"
  }
  option {
    name  = "UK West (Newport)"
    value = "uk-cardiff-1"
    icon  = "/emojis/1f1ec-1f1e7.png"
  }
  option {
    name  = "EU Central (Frankfurt)"
    value = "eu-frankfurt-1"
    icon  = "/emojis/1f1ea-1f1fa.png"
  }
  option {
    name  = "EU West (Amsterdam)"
    value = "eu-amsterdam-1"
    icon  = "/emojis/1f1ea-1f1fa.png"
  }
  option {
    name  = "EU South (Milan)"
    value = "eu-milan-1"
    icon  = "/emojis/1f1ea-1f1fa.png"
  }
  option {
    name  = "EU Central (Zurich)"
    value = "eu-zurich-1"
    icon  = "/emojis/1f1ea-1f1fa.png"
  }
  option {
    name  = "Asia Pacific (Mumbai)"
    value = "ap-mumbai-1"
    icon  = "/emojis/1f1ee-1f1f3.png"
  }
  option {
    name  = "Asia Pacific (Hyderabad)"
    value = "ap-hyderabad-1"
    icon  = "/emojis/1f1ee-1f1f3.png"
  }
  option {
    name  = "Asia Pacific (Seoul)"
    value = "ap-seoul-1"
    icon  = "/emojis/1f1f0-1f1f7.png"
  }
  option {
    name  = "Asia Pacific (Tokyo)"
    value = "ap-tokyo-1"
    icon  = "/emojis/1f1ef-1f1f5.png"
  }
  option {
    name  = "Asia Pacific (Osaka)"
    value = "ap-osaka-1"
    icon  = "/emojis/1f1ef-1f1f5.png"
  }
  option {
    name  = "Asia Pacific (Sydney)"
    value = "ap-sydney-1"
    icon  = "/emojis/1f1e6-1f1fa.png"
  }
  option {
    name  = "Asia Pacific (Melbourne)"
    value = "ap-melbourne-1"
    icon  = "/emojis/1f1e6-1f1fa.png"
  }
  option {
    name  = "Asia Pacific (Singapore)"
    value = "ap-singapore-1"
    icon  = "/emojis/1f1f8-1f1ec.png"
  }
  option {
    name  = "Middle East (Jeddah)"
    value = "me-jeddah-1"
    icon  = "/emojis/1f1f8-1f1e6.png"
  }
  option {
    name  = "Middle East (Dubai)"
    value = "me-dubai-1"
    icon  = "/emojis/1f1e6-1f1ea.png"
  }
}

# Instance shape parameter
data "coder_parameter" "instance_shape" {
  name         = "instance_shape"
  display_name = "Instance Shape"
  description  = "What instance shape should your workspace use?"
  default      = "VM.Standard.E2.1.Micro"
  mutable      = false
  option {
    name  = "1 OCPU, 1 GB RAM (Always Free)"
    value = "VM.Standard.E2.1.Micro"
  }
  option {
    name  = "1 OCPU, 6 GB RAM (Ampere)"
    value = "VM.Standard.A1.Flex"
  }
  option {
    name  = "1 OCPU, 8 GB RAM"
    value = "VM.Standard.E4.Flex"
  }
  option {
    name  = "2 OCPU, 16 GB RAM"
    value = "VM.Standard.E3.Flex"
  }
  option {
    name  = "4 OCPU, 32 GB RAM"
    value = "VM.Standard.E4.Flex"
  }
}

# Compartment OCID variable
variable "compartment_ocid" {
  description = "The OCID of the compartment where resources will be created"
  type        = string
  sensitive   = true
}

# Subnet OCID variable
variable "subnet_ocid" {
  description = "The OCID of the subnet where the instance will be created"
  type        = string
  sensitive   = true
}

# SSH public key variable
variable "ssh_public_key" {
  description = "SSH public key for instance access"
  type        = string
  sensitive   = true
}

provider "oci" {
  region = data.coder_parameter.region.value
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Get availability domains
data "oci_identity_availability_domains" "ads" {
  compartment_id = var.compartment_ocid
}

# Get the latest Ubuntu image
data "oci_core_images" "ubuntu" {
  compartment_id           = var.compartment_ocid
  operating_system         = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape                    = data.coder_parameter.instance_shape.value
  sort_by                  = "TIMECREATED"
  sort_order               = "DESC"
}

resource "coder_agent" "dev" {
  count          = data.coder_workspace.me.start_count
  arch           = "amd64"
  os             = "linux"
  startup_script = <<-EOT
    set -e

    # Prepare user home with default files on first start.
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~
      touch ~/.init_done
    fi

    # Install essential tools
    sudo apt-get update
    sudo apt-get install -y curl wget git build-essential

    # Add any commands that should be executed at workspace startup here
  EOT

  # Git configuration
  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
  }

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

# Code Server module
module "code-server" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/modules/code-server/coder"
  version = "~> 1.0"

  agent_id   = coder_agent.dev[0].id
  agent_name = "dev"
  order      = 1
}

# JetBrains module
module "jetbrains" {
  count      = data.coder_workspace.me.start_count
  source     = "registry.coder.com/modules/coder/jetbrains/coder"
  version    = "~> 1.0"
  agent_id   = coder_agent.dev[0].id
  agent_name = "dev"
  folder     = "/home/ubuntu"
}

locals {
  hostname   = lower(data.coder_workspace.me.name)
  linux_user = "ubuntu"
}

# Cloud-init configuration
data "cloudinit_config" "user_data" {
  gzip          = false
  base64_encode = true

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
      linux_user  = local.linux_user
      init_script = try(coder_agent.dev[0].init_script, "")
    })
  }
}

# OCI Compute Instance
resource "oci_core_instance" "dev" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = var.compartment_ocid
  display_name        = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
  shape               = data.coder_parameter.instance_shape.value

  # Shape config for flexible shapes
  dynamic "shape_config" {
    for_each = length(regexall("Flex", data.coder_parameter.instance_shape.value)) > 0 ? [1] : []
    content {
      ocpus         = 1
      memory_in_gbs = data.coder_parameter.instance_shape.value == "VM.Standard.A1.Flex" ? 6 : 8
    }
  }

  create_vnic_details {
    subnet_id        = var.subnet_ocid
    display_name     = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}-vnic"
    assign_public_ip = true
  }

  source_details {
    source_type = "image"
    source_id   = data.oci_core_images.ubuntu.images[0].id
  }

  metadata = {
    ssh_authorized_keys = var.ssh_public_key
    user_data           = data.cloudinit_config.user_data.rendered
  }

  freeform_tags = {
    "Coder_Provisioned" = "true"
    "Coder_Workspace"   = data.coder_workspace.me.name
    "Coder_Owner"       = data.coder_workspace_owner.me.name
  }

  lifecycle {
    ignore_changes = [source_details[0].source_id]
  }
}

# Instance state management
resource "oci_core_instance_action" "dev" {
  instance_id = oci_core_instance.dev.id
  action      = data.coder_workspace.me.transition == "start" ? "START" : "STOP"
}

# Workspace metadata
resource "coder_metadata" "workspace_info" {
  resource_id = oci_core_instance.dev.id
  item {
    key   = "region"
    value = data.coder_parameter.region.value
  }
  item {
    key   = "instance shape"
    value = oci_core_instance.dev.shape
  }
  item {
    key   = "public ip"
    value = oci_core_instance.dev.public_ip
  }
  item {
    key   = "availability domain"
    value = oci_core_instance.dev.availability_domain
  }
}
