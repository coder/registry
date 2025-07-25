terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
    }
  }
}

locals {
  icon_url = "/icon/code.svg"
  
  # Available development tools
  available_tools = {
    "git" = {
      name = "Git"
      description = "Version control system"
      install_command = "curl -fsSL https://raw.githubusercontent.com/git/git/master/contrib/completion/git-completion.bash > ~/.git-completion.bash"
    }
    "docker" = {
      name = "Docker"
      description = "Container runtime"
      install_command = "curl -fsSL https://get.docker.com | sh"
    }
    "nodejs" = {
      name = "Node.js"
      description = "JavaScript runtime"
      install_command = "curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - && sudo apt-get install -y nodejs"
    }
    "python" = {
      name = "Python"
      description = "Python programming language"
      install_command = "sudo apt-get update && sudo apt-get install -y python3 python3-pip python3-venv"
    }
    "golang" = {
      name = "Go"
      description = "Go programming language"
      install_command = "wget -q -O - https://git.io/vQhTU | bash"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "tools" {
  type        = list(string)
  description = "List of development tools to install. Available: git, docker, nodejs, python, golang"
  default     = ["git", "nodejs"]
  validation {
    condition = alltrue([
      for tool in var.tools : contains(["git", "docker", "nodejs", "python", "golang"], tool)
    ])
    error_message = "Invalid tool specified. Available tools: git, docker, nodejs, python, golang"
  }
}

variable "log_path" {
  type        = string
  description = "The path to log installation output to."
  default     = "/tmp/dev-tools-install.log"
}

variable "install_on_start" {
  type        = bool
  description = "Whether to install tools on workspace start."
  default     = true
}

variable "user" {
  type        = string
  description = "The user to install tools for."
  default     = "coder"
}

resource "coder_script" "dev-tools" {
  count              = var.install_on_start ? 1 : 0
  agent_id           = var.agent_id
  display_name       = "Install Development Tools"
  icon               = local.icon_url
  run_on_start       = true
  run_on_stop        = false
  start_blocks_login = false
  timeout            = 300

  script = templatefile("${path.module}/run.sh", {
    TOOLS = var.tools
    LOG_PATH = var.log_path
    USER = var.user
    AVAILABLE_TOOLS = local.available_tools
  })
}