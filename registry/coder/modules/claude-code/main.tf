terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.7"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation. The lowest order is shown first and apps with equal order are sorted by name (ascending order)."
  default     = null
}

variable "group" {
  type        = string
  description = "The name of a group that this app belongs to."
  default     = null
}

variable "icon" {
  type        = string
  description = "The icon to use for the app."
  default     = "/icon/claude.svg"
}

variable "folder" {
  type        = string
  description = "The folder to run Claude Code in."
  default     = "/home/coder"
}

variable "install_claude_code" {
  type        = bool
  description = "Whether to install Claude Code."
  default     = true
}

variable "claude_code_version" {
  type        = string
  description = "The version of Claude Code to install."
  default     = "latest"
}

variable "experiment_cli_app" {
  type        = bool
  description = "Whether to create the CLI workspace app."
  default     = false
}

variable "experiment_cli_app_order" {
  type        = number
  description = "The order of the CLI workspace app."
  default     = null
}

variable "experiment_cli_app_group" {
  type        = string
  description = "The group of the CLI workspace app."
  default     = null
}

variable "experiment_report_tasks" {
  type        = bool
  description = "Whether to enable task reporting."
  default     = false
}

variable "experiment_pre_install_script" {
  type        = string
  description = "Custom script to run before installing Claude Code."
  default     = null
}

variable "experiment_post_install_script" {
  type        = string
  description = "Custom script to run after installing Claude Code."
  default     = null
}


variable "install_agentapi" {
  type        = bool
  description = "Whether to install AgentAPI."
  default     = true
}

variable "agentapi_version" {
  type        = string
  description = "The version of AgentAPI to install."
  default     = "v0.2.3"
}

locals {
  # we have to trim the slash because otherwise coder exp mcp will
  # set up an invalid claude config 
  workdir                            = trimsuffix(var.folder, "/")
  encoded_pre_install_script         = var.experiment_pre_install_script != null ? base64encode(var.experiment_pre_install_script) : ""
  encoded_post_install_script        = var.experiment_post_install_script != null ? base64encode(var.experiment_post_install_script) : ""
  agentapi_start_script_b64          = base64encode(file("${path.module}/scripts/agentapi-start.sh"))
  agentapi_wait_for_start_script_b64 = base64encode(file("${path.module}/scripts/agentapi-wait-for-start.sh"))
  remove_last_session_id_script_b64  = base64encode(file("${path.module}/scripts/remove-last-session-id.js"))
  claude_code_app_slug               = "ccw"
}

# Install and Initialize Claude Code
resource "coder_script" "claude_code" {
  agent_id     = var.agent_id
  display_name = "Claude Code"
  icon         = var.icon
  script       = <<-EOT
    #!/bin/bash
    set -e
    set -x

    command_exists() {
      command -v "$1" >/dev/null 2>&1
    }

    if [ ! -d "${local.workdir}" ]; then
      echo "Warning: The specified folder '${local.workdir}' does not exist."
      echo "Creating the folder..."
      mkdir -p "${local.workdir}"
      echo "Folder created successfully."
    fi
    if [ -n "${local.encoded_pre_install_script}" ]; then
      echo "Running pre-install script..."
      echo "${local.encoded_pre_install_script}" | base64 -d > /tmp/pre_install.sh
      chmod +x /tmp/pre_install.sh
      /tmp/pre_install.sh
    fi

    if [ "${var.install_claude_code}" = "true" ]; then
      if ! command_exists npm; then
        echo "npm not found, checking for Node.js installation..."
        if ! command_exists node; then
          echo "Node.js not found, installing Node.js via NVM..."
          export NVM_DIR="$HOME/.nvm"
          if [ ! -d "$NVM_DIR" ]; then
            mkdir -p "$NVM_DIR"
            curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
          else
            [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
          fi
          
          nvm install --lts
          nvm use --lts
          nvm alias default node
          
          echo "Node.js installed: $(node --version)"
          echo "npm installed: $(npm --version)"
        else
          echo "Node.js is installed but npm is not available. Please install npm manually."
          exit 1
        fi
      fi
      echo "Installing Claude Code..."
      npm install -g @anthropic-ai/claude-code@${var.claude_code_version}
    fi

    if ! command_exists node; then
      echo "Error: Node.js is not installed. Please install Node.js manually."
      exit 1
    fi

    # Install AgentAPI if enabled
    if [ "${var.install_agentapi}" = "true" ]; then
      echo "Installing AgentAPI..."
      arch=$(uname -m)
      if [ "$arch" = "x86_64" ]; then
        binary_name="agentapi-linux-amd64"
      elif [ "$arch" = "aarch64" ]; then
        binary_name="agentapi-linux-arm64"
      else
        echo "Error: Unsupported architecture: $arch"
        exit 1
      fi
      curl \
        --retry 5 \
        --retry-delay 5 \
        --fail \
        --retry-all-errors \
        -L \
        -C - \
        -o agentapi \
        "https://github.com/coder/agentapi/releases/download/${var.agentapi_version}/$binary_name"
      chmod +x agentapi
      sudo mv agentapi /usr/local/bin/agentapi
    fi
    if ! command_exists agentapi; then
      echo "Error: AgentAPI is not installed. Please enable install_agentapi or install it manually."
      exit 1
    fi

    # this must be kept in sync with the agentapi-start.sh script
    module_path="$HOME/.claude-module"
    mkdir -p "$module_path/scripts"

    # save the prompt for the agentapi start command
    echo -n "$CODER_MCP_CLAUDE_TASK_PROMPT" > "$module_path/prompt.txt"

    echo -n "${local.agentapi_start_script_b64}" | base64 -d > "$module_path/scripts/agentapi-start.sh"
    echo -n "${local.agentapi_wait_for_start_script_b64}" | base64 -d > "$module_path/scripts/agentapi-wait-for-start.sh"
    echo -n "${local.remove_last_session_id_script_b64}" | base64 -d > "$module_path/scripts/remove-last-session-id.js"
    chmod +x "$module_path/scripts/agentapi-start.sh"
    chmod +x "$module_path/scripts/agentapi-wait-for-start.sh"

    if [ "${var.experiment_report_tasks}" = "true" ]; then
      echo "Configuring Claude Code to report tasks via Coder MCP..."
      export CODER_MCP_APP_STATUS_SLUG="${local.claude_code_app_slug}"
      export CODER_MCP_AI_AGENTAPI_URL="http://localhost:3284"
      coder exp mcp configure claude-code "${local.workdir}"
    fi

    if [ -n "${local.encoded_post_install_script}" ]; then
      echo "Running post-install script..."
      echo "${local.encoded_post_install_script}" | base64 -d > /tmp/post_install.sh
      chmod +x /tmp/post_install.sh
      /tmp/post_install.sh
    fi

    if ! command_exists claude; then
      echo "Error: Claude Code is not installed. Please enable install_claude_code or install it manually."
      exit 1
    fi

    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

    cd "${local.workdir}"
    nohup "$module_path/scripts/agentapi-start.sh" use_prompt &> "$module_path/agentapi-start.log" &
    "$module_path/scripts/agentapi-wait-for-start.sh"
    EOT
  run_on_start = true
}

resource "coder_app" "claude_code_web" {
  # use a short slug to mitigate https://github.com/coder/coder/issues/15178
  slug         = local.claude_code_app_slug
  display_name = "Claude Code Web"
  agent_id     = var.agent_id
  url          = "http://localhost:3284/"
  icon         = var.icon
  order        = var.order
  group        = var.group
  subdomain    = true
  healthcheck {
    url       = "http://localhost:3284/status"
    interval  = 3
    threshold = 20
  }
}

resource "coder_app" "claude_code" {
  count = var.experiment_cli_app ? 1 : 0

  slug         = "claude-code"
  display_name = "Claude Code CLI"
  agent_id     = var.agent_id
  command      = <<-EOT
    #!/bin/bash
    set -e

    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

    agentapi attach
    EOT
  icon         = var.icon
  order        = var.experiment_cli_app_order
  group        = var.experiment_cli_app_group
}

resource "coder_ai_task" "claude_code" {
  sidebar_app {
    id = coder_app.claude_code_web.id
  }
}
