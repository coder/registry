terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.0"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

provider "coder" {}
provider "docker" {}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Parameters for the template
data "coder_parameter" "image" {
  name         = "image"
  display_name = "Docker Image"
  description  = "Which Docker image would you like to use for your workspace?"
  default      = "codercom/enterprise-node:ubuntu"
  type         = "string"
  mutable      = false
  options {
    name  = "Node.js"
    value = "codercom/enterprise-node:ubuntu"
  }
  options {
    name  = "Python"
    value = "codercom/enterprise-python:ubuntu"
  }
  options {
    name  = "Java"
    value = "codercom/enterprise-java:ubuntu"
  }
  options {
    name  = "Go"
    value = "codercom/enterprise-golang:ubuntu"
  }
  options {
    name  = "Ruby"
    value = "codercom/enterprise-ruby:ubuntu"
  }
  options {
    name  = "Universal"
    value = "codercom/enterprise-base:ubuntu"
  }
}

data "coder_parameter" "auto_install_deps" {
  name         = "auto_install_deps"
  display_name = "Auto Install Dependencies"
  description  = "Automatically install project dependencies (npm install, pip install, etc.)"
  type         = "bool"
  default      = true
  mutable      = true
}

data "coder_parameter" "devcontainer_integration" {
  name         = "devcontainer_integration"
  display_name = "Devcontainer Integration"
  description  = "Enable integration with devcontainer.json configuration"
  type         = "bool"
  default      = true
  mutable      = true
}

# Docker resources
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
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "docker_image" "main" {
  name = data.coder_parameter.image.value
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.main.image_id
  # Uses lower() to avoid Docker restriction on container names.
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  # Hostname makes the shell more user friendly: coder@my-workspace:~$
  hostname = data.coder_workspace.me.name
  # Use the docker gateway if the access URL is 127.0.0.1
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env        = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/coder"
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

resource "coder_agent" "main" {
  arch           = data.coder_provisioner.me.arch
  os             = "linux"
  startup_script = <<-EOT
    set -e

    # Install common development tools if not present
    if ! command -v curl >/dev/null 2>&1; then
      sudo apt-get update
      sudo apt-get install -y curl wget git jq tmux
    fi

    # Install Node.js if not present (for npm/yarn/pnpm)
    if ! command -v node >/dev/null 2>&1; then
      curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
      sudo apt-get install -y nodejs
    fi

    # Create workspace directory if it doesn't exist
    mkdir -p /home/coder/workspace
    cd /home/coder/workspace

    # Example: Clone a sample project if workspace is empty
    if [ ! "$(ls -A /home/coder/workspace)" ]; then
      echo "Workspace is empty, cloning sample projects..."
      
      # Node.js example
      git clone https://github.com/vercel/next.js.git nextjs-example || true
      
      # Python example  
      git clone https://github.com/tiangolo/fastapi.git fastapi-example || true
      
      echo "Sample projects cloned. Navigate to a project directory to start development!"
    fi
  EOT
  dir            = "/home/coder/workspace"

  # Git configuration
  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = data.coder_workspace_owner.me.email
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = data.coder_workspace_owner.me.email
  }

  # Metadata for resource monitoring
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

# Auto-start development servers
module "dev_server_autostart" {
  count    = data.coder_workspace.me.start_count
  source   = "../../registry/coder/modules/dev-server-autostart"
  agent_id = coder_agent.main.id
  
  # Configuration
  work_dir                 = "/home/coder/workspace"
  scan_subdirectories     = true
  max_depth               = 3
  
  # Dependency management
  auto_install_deps       = data.coder_parameter.auto_install_deps.value
  
  # Devcontainer support
  devcontainer_integration = data.coder_parameter.devcontainer_integration.value
  
  # Custom commands for different frameworks
  custom_commands = {
    "node"    = "npm run dev || npm start"
    "nextjs"  = "npm run dev"
    "python"  = "python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000"
    "django"  = "python manage.py runserver 0.0.0.0:8000"
    "fastapi" = "uvicorn main:app --reload --host 0.0.0.0 --port 8000"
  }
  
  # Framework preferences
  disabled_frameworks = []
  
  # Timing and health checks
  startup_delay        = 10  # Wait for workspace to fully initialize
  health_check_enabled = true
  timeout_seconds      = 300
  
  # Logging
  log_level = "info"
}

# Code Server for VS Code in browser
module "code_server" {
  count    = data.coder_workspace.me.start_count
  source   = "../../registry/coder/modules/code-server"
  agent_id = coder_agent.main.id
  
  folder = "/home/coder/workspace"
  
  # Extensions for development
  extensions = [
    "ms-python.python",
    "bradlc.vscode-tailwindcss",
    "esbenp.prettier-vscode",
    "dbaeumer.vscode-eslint",
    "ms-vscode.vscode-typescript-next",
    "golang.go",
    "rust-lang.rust-analyzer",
  ]
  
  settings = {
    "workbench.colorTheme" = "GitHub Dark Default"
    "editor.fontSize" = 14
    "editor.tabSize" = 2
    "editor.insertSpaces" = true
    "files.autoSave" = "afterDelay"
    "terminal.integrated.fontSize" = 14
  }
}

# Create development server apps for common ports
resource "coder_app" "dev_server_3000" {
  agent_id     = coder_agent.main.id
  slug         = "dev-3000"
  display_name = "Development Server (3000)"
  url          = "http://localhost:3000"
  icon         = "/icon/web.svg"
  subdomain    = false
  share        = "owner"
  
  healthcheck {
    url       = "http://localhost:3000"
    interval  = 5
    threshold = 6
  }
}

resource "coder_app" "dev_server_8000" {
  agent_id     = coder_agent.main.id
  slug         = "dev-8000"
  display_name = "Development Server (8000)"
  url          = "http://localhost:8000"
  icon         = "/icon/web.svg"
  subdomain    = false
  share        = "owner"
  
  healthcheck {
    url       = "http://localhost:8000"
    interval  = 5
    threshold = 6
  }
}

resource "coder_app" "dev_server_4200" {
  agent_id     = coder_agent.main.id
  slug         = "dev-4200"
  display_name = "Development Server (4200)"
  url          = "http://localhost:4200"
  icon         = "/icon/web.svg"
  subdomain    = false
  share        = "owner"
  
  healthcheck {
    url       = "http://localhost:4200"
    interval  = 5
    threshold = 6
  }
}

resource "coder_app" "dev_server_5000" {
  agent_id     = coder_agent.main.id
  slug         = "dev-5000"
  display_name = "Development Server (5000)"
  url          = "http://localhost:5000"
  icon         = "/icon/web.svg"
  subdomain    = false
  share        = "owner"
  
  healthcheck {
    url       = "http://localhost:5000"
    interval  = 5
    threshold = 6
  }
}

# Display information about auto-started services
resource "coder_metadata" "dev_server_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = coder_agent.main.id
  
  item {
    key   = "Auto-start enabled"
    value = "Development servers will auto-start based on detected project types"
  }
  
  item {
    key   = "Supported frameworks"
    value = "Node.js, Python, Ruby, Go, Java, PHP, Next.js, React, Vue.js, Angular"
  }
  
  item {
    key   = "Working directory"
    value = "/home/coder/workspace"
  }
  
  item {
    key   = "Logs location"
    value = "/tmp/dev-server-autostart/"
  }
  
  item {
    key   = "View running servers"
    value = "Run 'tmux list-sessions' to see active development servers"
  }
}
