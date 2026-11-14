terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI"
  type        = string
}

provider "docker" {
  # Defaulting to null if the variable is an empty string lets us have an optional variable without having to set our own default
  host = var.docker_socket != "" ? var.docker_socket : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "coder_parameter" "gpu" {
  name         = "gpu"
  display_name = "GPU"
  description  = "The GPU the desktop renders and encodes the stream on. NVIDIA needs the NVIDIA Container Toolkit on the Docker host."
  default      = "none"
  mutable      = true
  option {
    name  = "None"
    value = "none"
  }
  option {
    name  = "NVIDIA"
    value = "nvidia"
  }
}

data "coder_parameter" "display_backend" {
  name         = "display_backend"
  display_name = "Display backend"
  description  = "The display server the desktop runs on."
  default      = "x11"
  mutable      = true
  option {
    name  = "X11"
    value = "x11"
  }
  option {
    name  = "Wayland"
    value = "wayland"
  }
}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

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
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }
}

# See https://registry.coder.com/modules/selkies-project/selkies
module "selkies" {
  count           = data.coder_workspace.me.start_count
  source          = "registry.coder.com/selkies-project/selkies/coder"
  version         = "~> 1.0"
  agent_id        = coder_agent.main.id
  install_selkies = false
  wayland         = data.coder_parameter.display_backend.value == "wayland"
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  # Selkies' desktop image: LXQt, Firefox, and Chrome, with Selkies and Xvfb installed
  image = "ghcr.io/selkies-project/selkies/desktop:latest-ubuntu26.04"
  # Uses lower() to avoid Docker restriction on container names.
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  # Hostname makes the shell more user friendly: ubuntu@my-workspace:~$
  hostname = data.coder_workspace.me.name
  # The agent runs in place of the image's own init, and the module starts the desktop and Selkies
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    # The image asks for every NVIDIA GPU, which a host whose default runtime is NVIDIA's would otherwise pass in
    "NVIDIA_VISIBLE_DEVICES=${data.coder_parameter.gpu.value == "nvidia" ? "all" : "void"}",
  ]
  gpus    = data.coder_parameter.gpu.value == "nvidia" ? "all" : null
  runtime = data.coder_parameter.gpu.value == "nvidia" ? "nvidia" : null
  # Browsers crash in Docker's default 64 MB of shared memory
  shm_size = 2048
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/ubuntu"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }

  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}
