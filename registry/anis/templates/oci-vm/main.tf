terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    oci = {
      source = "oracle/oci"
    }
  }
}

variable "tenancy_ocid" {
  description = "Tenancy OCID"
  type        = string
  default     = ""
}

variable "compartment_ocid" {
  description = "Compartment OCID"
  type        = string
  default     = ""
}

variable "user_ocid" {
  description = "User OCID"
  type        = string
  default     = ""
}

variable "fingerprint" {
  description = "fingerprint"
  type        = string
  default     = ""
}

variable "private_key" {
  description = "Private Key File"
  type        = string
  default     = ""
}

variable "subnet_id" {
  description = "Subnet OCID"
  type        = string
  default     = ""
}

variable "ssh_public_key" {
  description = "SSH public key for debugging access"
  type        = string
  default     = ""
}

data "coder_parameter" "region" {
  name         = "region"
  display_name = "Region"
  description  = "The region to deploy the workspace in."
  default      = "eu-marseille-1"
  mutable      = false
  option {
    name  = "France South (Marseille)"
    value = "eu-marseille-1"
    icon  = "/emojis/1f1eb-1f1f7.png"
  }
  option {
    name  = "France Central (Paris)"
    value = "eu-paris-1"
    icon  = "/emojis/1f1eb-1f1f7.png"
  }
  option {
    name  = "UK South (London)"
    value = "uk-london-1"
    icon  = "/emojis/1f1ea-1f1fa.png"
  }
  option {
    name  = "Germany Central (Frankfurt)"
    value = "eu-frankfurt-1"
    icon  = "/emojis/1f1ea-1f1fa.png"
  }
  option {
    name  = "US West (Phoenix)"
    value = "us-phoenix-1"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "US East (Ashburn)"
    value = "us-ashburn-1"
    icon  = "/emojis/1f1fa-1f1f8.png"
  }
  option {
    name  = "Australia Southeast (Sydney)"
    value = "ap-sydney-1"
    icon  = "/emojis/1f1e6-1f1fa.png"
  }
}
data "coder_parameter" "instance_type" {
  name         = "instance_type"
  display_name = "Instance type"
  description  = "What instance type should your workspace use?"
  default      = "VM.Standard.E3.Flex"
  mutable      = false
  option {
    name  = "VM.Standard.E3.Flex"
    value = "VM.Standard.E3.Flex"
  }
}

data "coder_parameter" "instance_ocpus" {
  name         = "instance_ocpus"
  display_name = "OCPUs"
  description  = "Number of OCPUs (only for Flex shapes)"
  type         = "number"
  default      = 1
  mutable      = true
  option {
    name  = "1 OCPU"
    value = 1
  }
  option {
    name  = "2 OCPUs"
    value = 2
  }
  option {
    name  = "4 OCPUs"
    value = 4
  }
  option {
    name  = "8 OCPUs"
    value = 8
  }
}

data "coder_parameter" "instance_memory" {
  name         = "instance_memory"
  display_name = "Memory (GB)"
  description  = "Amount of RAM (only for Flex shapes). Must be >= OCPUs (min 1:1 ratio) and <= 64x OCPUs (max 1:64 ratio)"
  type         = "number"
  default      = 2
  mutable      = true
  option {
    name  = "1 GB"
    value = 1
  }
  option {
    name  = "2 GB"
    value = 2
  }
  option {
    name  = "4 GB"
    value = 4
  }
  option {
    name  = "8 GB"
    value = 8
  }
  option {
    name  = "16 GB"
    value = 16
  }
  option {
    name  = "32 GB"
    value = 32
  }
  
  validation {
    min     = data.coder_parameter.instance_ocpus.value
    error = "Memory must be at least equal to OCPUs (minimum 1:1 ratio)."
  }
  
}

provider "oci" {
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key      = var.private_key
  region           = data.coder_parameter.region.value
}


data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"

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
    key          = "home"
    display_name = "Home Usage"
    interval     = 600 # every 10 minutes
    timeout      = 30  # df can take a while on large filesystems
    script       = "coder stat disk --path /home/${lower(data.coder_workspace_owner.me.name)}"
  }
}

locals {
  compartment_id    = var.compartment_ocid != "" ? var.compartment_ocid : var.tenancy_ocid
  vm_name           = "coder-${lower(data.coder_workspace_owner.me.name)}-${lower(data.coder_workspace.me.name)}"
  root_disk_label   = substr("${local.vm_name}-root", 0, 32)
  home_volume_label = substr("${local.vm_name}-home", 0, 32)
}

data "oci_core_images" "ubuntu_image" {
  compartment_id = local.compartment_id
  operating_system = "Canonical Ubuntu"
  operating_system_version = "22.04"
  shape = data.coder_parameter.instance_type.value
}

data "oci_identity_availability_domains" "ads" {
  compartment_id = local.compartment_id
}

data "coder_parameter" "home_volume_size" {
  name         = "home_volume_size"
  display_name = "Home Volume Size (GB)"
  description  = "How large would you like your home volume to be (in GB)?"
  type         = "number"
  default      = 50
  mutable      = true
  order       = 3
  option {
    name  = "50GB"
    value = 50
  }
  option {
    name  = "60GB"
    value = 60
  }
  option {
    name  = "70GB"
    value = 700
  }

  validation {
    monotonic = "increasing"
  }
}

resource "oci_core_instance" "workspace" {
    count = data.coder_workspace.me.start_count
    availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
    compartment_id = local.compartment_id
    shape = data.coder_parameter.instance_type.value
    dynamic "shape_config" {
        for_each = can(regex("Flex", data.coder_parameter.instance_type.value)) ? [1] : []
        content {
            ocpus         = data.coder_parameter.instance_ocpus.value
            memory_in_gbs = data.coder_parameter.instance_memory.value
        }
    }
    source_details {
        source_type = "image"
        source_id   = data.oci_core_images.ubuntu_image.images[0].id
    }
    display_name = local.vm_name
    create_vnic_details {
        assign_public_ip = true
        subnet_id = var.subnet_id
    }
    metadata = {
        user_data = base64encode(templatefile("cloud-init/cloud-config.yaml.tftpl", {
            hostname          = local.vm_name
            username          = lower(data.coder_workspace_owner.me.name)
            home_volume_label = local.home_volume_label
            init_script       = base64encode(coder_agent.main.init_script)
            coder_agent_token = coder_agent.main.token
        }))
    } 
}

resource "oci_core_volume" "home_volume" {
  availability_domain = data.oci_identity_availability_domains.ads.availability_domains[0].name
  compartment_id      = local.compartment_id
  display_name        = local.home_volume_label
  size_in_gbs         = data.coder_parameter.home_volume_size.value
}

resource "oci_core_volume_attachment" "attach_home" {
  count           = data.coder_workspace.me.start_count
  attachment_type = "paravirtualized"
  compartment_id  = local.compartment_id
  instance_id     = oci_core_instance.workspace[0].id
  #device           = "/dev/sdb"
  volume_id       = oci_core_volume.home_volume.id
}

module "code-server" {
  count   = data.coder_workspace.me.start_count
  source  = "registry.coder.com/coder/code-server/coder"
  version = "~> 1.0"

  agent_id = coder_agent.main.id
  order    = 1
}

resource "coder_metadata" "workspace-info" {
  count       = data.coder_workspace.me.start_count
  resource_id = oci_core_instance.workspace[0].id

  item {
    key   = "region"
    value = data.coder_parameter.region.value
  }
  item {
    key   = "type"
    value = data.coder_parameter.instance_type.value
  }
}