terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.5"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# VS Code Desktop Enhanced with pre-installed extensions and settings
module "vscode_enhanced" {
  count    = data.coder_workspace.me.start_count
  source   = "../../registry/coder/modules/vscode-desktop-enhanced"
  agent_id = coder_agent.main.id
  folder   = "/home/coder/workspace"
  order    = 1

  # Development extensions for Python and TypeScript
  extensions = [
    "ms-python.python",
    "ms-vscode.vscode-typescript-next",
    "esbenp.prettier-vscode",
    "ms-vscode.vscode-eslint",
    "ms-vscode.vscode-json"
  ]

  # Team settings for consistent development
  settings = jsonencode({
    "editor.formatOnSave" = true
    "editor.tabSize" = 2
    "editor.insertSpaces" = true
    "prettier.singleQuote" = true
    "prettier.trailingComma" = "es5"
    "workbench.colorTheme" = "Dark+ (default dark)"
    "files.autoSave" = "afterDelay"
    "files.autoSaveDelay" = 1000
    "editor.fontSize" = 14
    "terminal.integrated.defaultProfile.linux" = "bash"
    "python.defaultInterpreterPath" = "/usr/bin/python3"
    "workbench.startupEditor" = "newUntitledFile"
  })
}

# Docker container
resource "docker_image" "main" {
  name = "codercom/enterprise-base:ubuntu"
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.main.image_id
  # Uses lower() to avoid Docker restriction on container names.
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  # Hostname makes the shell more user friendly: coder@my-workspace:~$
  hostname = data.coder_workspace.me.name
  # Use the docker gateway if the access URL is localhost
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/coder"
    host_path      = "${path.cwd}/home"
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

resource "coder_agent" "main" {
  arch                   = data.coder_provisioner.me.arch
  os                     = "linux"
  startup_script_timeout = 180
  startup_script         = <<-EOT
    set -e

    # Install development tools and VS Code CLI
    sudo apt-get update
    sudo apt-get install -y \
      curl \
      git \
      golang \
      sudo \
      vim \
      wget \
      nodejs \
      npm \
      python3 \
      python3-pip \
      jq

    # Create workspace directory
    mkdir -p /home/coder/workspace
    
    # Install global npm packages
    sudo npm install -g typescript prettier eslint

    # Make sure VS Code server directories exist
    mkdir -p /home/coder/.vscode-server/extensions
    
    EOT

  # The following metadata blocks are optional. They are used to display
  # information about your workspace in the dashboard. You can remove them
  # if you don't want to display any information.
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
    script       = "coder stat disk --path /home/coder"
    interval     = 60
    timeout      = 1
  }
}

# code-server
resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code Web"
  url          = "http://localhost:13337/?folder=/home/coder/workspace"
  icon         = "/icon/code.svg"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

resource "coder_script" "code-server" {
  agent_id     = coder_agent.main.id
  display_name = "VS Code Web Server"
  icon         = "/icon/code.svg"
  script = templatefile("${path.module}/code-server.sh", {
    folder = "/home/coder/workspace"
  })
  run_on_start = true
}
