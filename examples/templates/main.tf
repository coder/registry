terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    # Add your provider here (e.g., docker, aws, gcp, azure)
    # docker = {
    #   source = "kreuzwerker/docker"
    # }
  }
}

locals {
  username = data.coder_workspace_owner.me.name
}

# Add your variables here
# variable "example_var" {
#   default     = "default_value"
#   description = "Description of the variable"
#   type        = string
# }

# Configure your provider here
# provider "docker" {
#   host = var.docker_socket != "" ? var.docker_socket : null
# }

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = <<-EOT
    set -e

    # Prepare user home with default files on first start.
    if [ ! -f ~/.init_done ]; then
      cp -rT /etc/skel ~
      touch ~/.init_done
    fi

    # Add any commands that should be executed at workspace startup here
  EOT

  # These environment variables allow you to make Git commits right away after creating a
  # workspace. Note that they take precedence over configuration defined in ~/.gitconfig!
  # You can remove this block if you'd prefer to configure Git manually or using
  # dotfiles. (see docs/dotfiles.md)
  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
  }

  # The following metadata blocks are optional. They are used to display
  # information about your workspace in the dashboard. You can remove them
  # if you don't want to display any information.
  # For basic templates, you can remove the "display_apps" block.
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

  display_apps {
    vscode                 = true
    vscode_insiders        = false
    ssh_helper             = false
    port_forwarding_helper = true
    web_terminal           = true
  }
}

# Add your resources here (e.g., docker container, VM, etc.)
# resource "docker_image" "main" {
#   name = "codercom/enterprise-base:ubuntu"
# }

# resource "docker_container" "workspace" {
#   count = data.coder_workspace.me.start_count
#   image = docker_image.main.image_id
#   # Uses lower() to avoid Docker restriction on container names.
#   name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
#   # Hostname makes the shell more user friendly: coder@my-workspace:~$
#   hostname = data.coder_workspace.me.name
#   # Use the docker gateway if the access URL is 127.0.0.1
#   entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\.0\.0\.1/", "host.docker.internal")]
#   env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
#   host {
#     host = "host.docker.internal"
#     ip   = "host-gateway"
#   }
#   volumes {
#     container_path = "/home/${local.username}"
#     volume_name    = docker_volume.home_volume[0].name
#     read_only      = false
#   }
#   # Add labels in Docker to keep track of orphan resources.
#   labels {
#     label = "coder.owner"
#     value = data.coder_workspace_owner.me.name
#   }
#   labels {
#     label = "coder.owner_id"
#     value = data.coder_workspace_owner.me.id
#   }
#   labels {
#     label = "coder.workspace_id"
#     value = data.coder_workspace.me.id
#   }
#   labels {
#     label = "coder.workspace_name"
#     value = data.coder_workspace.me.name
#   }
# }

# resource "docker_volume" "home_volume" {
#   count = data.coder_workspace.me.start_count
#   name  = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}-home"
#   # Protect the volume from being deleted due to changes in attributes.
#   lifecycle {
#     ignore_changes = all
#   }
#   # Add labels in Docker to keep track of orphan resources.
#   labels {
#     label = "coder.owner"
#     value = data.coder_workspace_owner.me.name
#   }
#   labels {
#     label = "coder.owner_id"
#     value = data.coder_workspace_owner.me.id
#   }
#   labels {
#     label = "coder.workspace_id"
#     value = data.coder_workspace.me.id
#   }
#   labels {
#     label = "coder.workspace_name"
#     value = data.coder_workspace.me.name
#   }
# }

resource "coder_metadata" "workspace_info" {
  resource_id = coder_agent.main.id

  item {
    key   = "TEMPLATE_NAME"
    value = "TEMPLATE_NAME"
  }
}
