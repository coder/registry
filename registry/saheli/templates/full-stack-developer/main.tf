terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
  }
}

# Authentication
data "coder_parameter" "image" {
  type         = "string"
  name         = "image"
  display_name = "Container Image"
  description  = "Base container image for development"
  icon         = "/icon/docker.svg"
  mutable      = false
  default      = "codercom/enterprise-base:ubuntu"
  option {
    name  = "Ubuntu (Latest)"
    value = "codercom/enterprise-base:ubuntu"
    icon  = "/icon/ubuntu.svg"
  }
  option {
    name  = "Node.js"
    value = "codercom/enterprise-node:ubuntu"
    icon  = "/icon/nodejs.svg"
  }
  option {
    name  = "Python"
    value = "codercom/enterprise-python:ubuntu"
    icon  = "/icon/python.svg"
  }
  option {
    name  = "Go"
    value = "codercom/enterprise-golang:ubuntu"
    icon  = "/icon/go.svg"
  }
}

data "coder_parameter" "repo_url" {
  type         = "string"
  name         = "repo_url"
  display_name = "Repository URL"
  description  = "Git repository to clone (optional)"
  icon         = "/icon/git.svg"
  mutable      = true
  default      = ""
}

data "coder_parameter" "jetbrains_ides" {
  type         = "list(string)"
  name         = "jetbrains_ides"
  display_name = "JetBrains IDEs"
  description  = "Select JetBrains IDEs to configure"
  icon         = "/icon/jetbrains.svg"
  mutable      = true
  default      = jsonencode(["IU"])
  
  option {
    name  = "IntelliJ IDEA Ultimate"
    value = "IU"
    icon  = "/icon/intellij.svg"
  }
  option {
    name  = "PyCharm Professional"
    value = "PY"
    icon  = "/icon/pycharm.svg"
  }
  option {
    name  = "WebStorm"
    value = "WS"
    icon  = "/icon/webstorm.svg"
  }
  option {
    name  = "GoLand"
    value = "GO"
    icon  = "/icon/goland.svg"
  }
  option {
    name  = "PhpStorm"
    value = "PS"
    icon  = "/icon/phpstorm.svg"
  }
  option {
    name  = "Rider"
    value = "RD"
    icon  = "/icon/rider.svg"
  }
  option {
    name  = "CLion"
    value = "CL"
    icon  = "/icon/clion.svg"
  }
  option {
    name  = "RubyMine"
    value = "RM"
    icon  = "/icon/rubymine.svg"
  }
  option {
    name  = "RustRover"
    value = "RR"
    icon  = "/icon/rustrover.svg"
  }
}

data "coder_parameter" "dev_tools" {
  type         = "list(string)"
  name         = "dev_tools"
  display_name = "Development Tools"
  description  = "Select development tools to install"
  icon         = "/icon/code.svg"
  mutable      = true
  default      = jsonencode(["git", "nodejs"])
  
  option {
    name  = "Git"
    value = "git"
    icon  = "/icon/git.svg"
  }
  option {
    name  = "Docker"
    value = "docker"
    icon  = "/icon/docker.svg"
  }
  option {
    name  = "Node.js"
    value = "nodejs"
    icon  = "/icon/nodejs.svg"
  }
  option {
    name  = "Python"
    value = "python"
    icon  = "/icon/python.svg"
  }
  option {
    name  = "Go"
    value = "golang"
    icon  = "/icon/go.svg"
  }
}

locals {
  username = data.coder_workspace.me.owner
  
  # JetBrains plugins based on selected IDEs and tools
  jetbrains_plugins = flatten([
    # Essential plugins for all IDEs
    [
      "org.jetbrains.plugins.github",           # GitHub integration
      "com.intellij.ml.llm",                    # AI Assistant
      "org.intellij.plugins.markdown",          # Markdown support
      "com.intellij.plugins.textmate"           # TextMate bundles
    ],
    
    # Language-specific plugins based on selected tools
    contains(jsondecode(data.coder_parameter.dev_tools.value), "python") ? [
      "Pythonid"                                # Python support for IntelliJ
    ] : [],
    
    contains(jsondecode(data.coder_parameter.dev_tools.value), "golang") ? [
      "org.jetbrains.plugins.go"               # Go support
    ] : [],
    
    contains(jsondecode(data.coder_parameter.dev_tools.value), "nodejs") ? [
      "JavaScript",                             # JavaScript support
      "org.intellij.plugins.vue"               # Vue.js support
    ] : [],
    
    contains(jsondecode(data.coder_parameter.dev_tools.value), "docker") ? [
      "Docker"                                  # Docker integration
    ] : []
  ])
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Container
resource "docker_image" "main" {
  name = data.coder_parameter.image.value
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  lifecycle {
    ignore_changes = all
  }
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

# Workspace container
resource "docker_container" "workspace" {
  count   = data.coder_workspace.me.start_count
  image   = docker_image.main.image_id
  name    = "coder-${data.coder_workspace_owner.me.name}-${data.coder_workspace.me.name}"
  hostname = data.coder_workspace.me.name
  
  # Use the docker gateway if the access URL is 127.0.0.1
  entrypoint = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  
  env = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  
  volumes {
    container_path = "/home/${local.username}"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
  
  # Add the Docker socket for development
  volumes {
    container_path = "/var/run/docker.sock"
    host_path      = "/var/run/docker.sock"
    read_only      = false
  }
  
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

# Coder agent
resource "coder_agent" "main" {
  os                     = "linux"
  arch                   = data.coder_provisioner.me.arch
  login_before_ready     = false
  startup_script_timeout = 180
  startup_script_behavior = "blocking"

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

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }
}

# Git repository cloning (if provided)
module "git_clone" {
  count    = data.coder_parameter.repo_url.value != "" ? 1 : 0
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  url      = data.coder_parameter.repo_url.value
}

# Development tools installation
module "dev_tools" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"  # Using existing module for now
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  folder   = "/home/${local.username}"
  
  # Note: This will be updated to saheli/dev-tools once published
  extensions = [
    "ms-vscode.vscode-json",
    "redhat.vscode-yaml"
  ]
}

# VS Code Server
module "code_server" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  folder   = data.coder_parameter.repo_url.value != "" ? "/home/${local.username}/${split("/", data.coder_parameter.repo_url.value)[length(split("/", data.coder_parameter.repo_url.value)) - 1]}" : "/home/${local.username}"
  
  extensions = flatten([
    # Essential extensions
    [
      "ms-vscode.vscode-json",
      "redhat.vscode-yaml",
      "ms-vscode.vscode-typescript-next",
      "bradlc.vscode-tailwindcss"
    ],
    
    # Language-specific extensions based on selected tools
    contains(jsondecode(data.coder_parameter.dev_tools.value), "python") ? [
      "ms-python.python",
      "ms-python.pylint"
    ] : [],
    
    contains(jsondecode(data.coder_parameter.dev_tools.value), "golang") ? [
      "golang.go"
    ] : [],
    
    contains(jsondecode(data.coder_parameter.dev_tools.value), "nodejs") ? [
      "ms-vscode.vscode-node-debug2",
      "ms-vscode.vscode-eslint"
    ] : [],
    
    contains(jsondecode(data.coder_parameter.dev_tools.value), "docker") ? [
      "ms-azuretools.vscode-docker"
    ] : []
  ])
  
  order = 1
}

# JetBrains IDEs with plugin pre-configuration
module "jetbrains_with_plugins" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/jetbrains/coder"  # Using existing module for now
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
  folder   = data.coder_parameter.repo_url.value != "" ? "/home/${local.username}/${split("/", data.coder_parameter.repo_url.value)[length(split("/", data.coder_parameter.repo_url.value)) - 1]}" : "/home/${local.username}"
  
  # Configure selected IDEs
  default = jsondecode(data.coder_parameter.jetbrains_ides.value)
  
  # Note: Plugin pre-configuration will be available once saheli/jetbrains-plugins is published
}

# Environment personalization
module "dotfiles" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/dotfiles/coder"
  version  = "~> 1.0"
  agent_id = coder_agent.main.id
}

# Workspace information
resource "coder_metadata" "workspace_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = docker_container.workspace[0].id

  item {
    key   = "image"
    value = data.coder_parameter.image.value
  }
  
  item {
    key   = "selected_tools"
    value = join(", ", jsondecode(data.coder_parameter.dev_tools.value))
  }
  
  item {
    key   = "selected_ides"
    value = join(", ", jsondecode(data.coder_parameter.jetbrains_ides.value))
  }
  
  item {
    key   = "repository"
    value = data.coder_parameter.repo_url.value != "" ? data.coder_parameter.repo_url.value : "None"
  }
  
  item {
    key   = "configured_plugins"
    value = "${length(local.jetbrains_plugins)} JetBrains plugins"
  }
}