terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.5"
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

variable "experiment_use_screen" {
  type        = bool
  description = "Whether to use screen for running Claude Code in the background."
  default     = false
}

variable "experiment_use_tmux" {
  type        = bool
  description = "Whether to use tmux instead of screen for running Claude Code in the background."
  default     = false
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

locals {
  encoded_pre_install_script  = var.experiment_pre_install_script != null ? base64encode(var.experiment_pre_install_script) : ""
  encoded_post_install_script = var.experiment_post_install_script != null ? base64encode(var.experiment_post_install_script) : ""
}

# Install and Initialize Claude Code
resource "coder_script" "claude_code" {
  agent_id     = var.agent_id
  display_name = "Claude Code"
  icon         = var.icon
  script       = <<-EOT
    #!/bin/bash
    set -e

    # Function to check if a command exists
    command_exists() {
      command -v "$1" >/dev/null 2>&1
    }

    # Check if the specified folder exists
    if [ ! -d "${var.folder}" ]; then
      echo "Warning: The specified folder '${var.folder}' does not exist."
      echo "Creating the folder..."
      # The folder must exist before tmux is started or else claude will start
      # in the home directory.
      mkdir -p "${var.folder}"
      echo "Folder created successfully."
    fi

    # Run pre-install script if provided
    if [ -n "${local.encoded_pre_install_script}" ]; then
      echo "Running pre-install script..."
      echo "${local.encoded_pre_install_script}" | base64 -d > /tmp/pre_install.sh
      chmod +x /tmp/pre_install.sh
      /tmp/pre_install.sh
    fi

    # Install Claude Code if enabled
    if [ "${var.install_claude_code}" = "true" ]; then
      if ! command_exists npm; then
        echo "Error: npm is not installed. Please install Node.js and npm first."
        exit 1
      fi
      echo "Installing Claude Code..."
      npm install -g @anthropic-ai/claude-code@${var.claude_code_version}
    fi

    # Hardcoded for now: install AgentAPI
    wget https://github.com/coder/agentapi/releases/download/preview/agentapi-linux-amd64
    chmod +x agentapi-linux-amd64
    sudo mv agentapi-linux-amd64 /usr/local/bin/agentapi

    if [ "${var.experiment_report_tasks}" = "true" ]; then
      echo "Configuring Claude Code to report tasks via Coder MCP..."
      coder exp mcp configure claude-code ${var.folder}
    fi

    # Run post-install script if provided
    if [ -n "${local.encoded_post_install_script}" ]; then
      echo "Running post-install script..."
      echo "${local.encoded_post_install_script}" | base64 -d > /tmp/post_install.sh
      chmod +x /tmp/post_install.sh
      /tmp/post_install.sh
    fi

    # Handle terminal multiplexer selection (tmux or screen)
    if [ "${var.experiment_use_tmux}" = "true" ] && [ "${var.experiment_use_screen}" = "true" ]; then
      echo "Error: Both experiment_use_tmux and experiment_use_screen cannot be true simultaneously."
      echo "Please set only one of them to true."
      exit 1
    fi

    # Run with tmux if enabled
    if [ "${var.experiment_use_tmux}" = "true" ]; then
      echo "Running Claude Code in the background with tmux..."

      # Check if tmux is installed
      if ! command_exists tmux; then
        echo "Error: tmux is not installed. Please install tmux manually."
        exit 1
      fi

      touch "$HOME/.claude-code.log"

      export LANG=en_US.UTF-8
      export LC_ALL=en_US.UTF-8

      # use low width to fit in the tasks UI sidebar. height is adjusted to ~match the default 80k (80x1000) characters
      # visible in the terminal screen.
      tmux new-session -d -s claude-code-agentapi -c ${var.folder} 'agentapi server --term-width 56 --term-height 1425 -- bash -c "claude --dangerously-skip-permissions \"$CODER_MCP_CLAUDE_TASK_PROMPT\" | tee -a \"$HOME/.claude-code.log\""; exec bash'
      echo "Waiting for agentapi server to start on port 3284..."
      for i in $(seq 1 15); do
        if lsof -i :3284 | grep -q 'LISTEN'; then
          echo "agentapi server started on port 3284."
          break
        fi
        echo "Waiting... ($i/15)"
        sleep 1
      done
      if ! lsof -i :3284 | grep -q 'LISTEN'; then
        echo "Error: agentapi server did not start on port 3284 after 15 seconds."
        exit 1
      fi
      tmux new-session -d -s claude-code -c ${var.folder} "agentapi attach"


    fi

    # Run with screen if enabled
    if [ "${var.experiment_use_screen}" = "true" ]; then
      echo "Running Claude Code in the background..."

      # Check if screen is installed
      if ! command_exists screen; then
        echo "Error: screen is not installed. Please install screen manually."
        exit 1
      fi

      touch "$HOME/.claude-code.log"

      # Ensure the screenrc exists
      if [ ! -f "$HOME/.screenrc" ]; then
        echo "Creating ~/.screenrc and adding multiuser settings..." | tee -a "$HOME/.claude-code.log"
        echo -e "multiuser on\nacladd $(whoami)" > "$HOME/.screenrc"
      fi

      if ! grep -q "^multiuser on$" "$HOME/.screenrc"; then
        echo "Adding 'multiuser on' to ~/.screenrc..." | tee -a "$HOME/.claude-code.log"
        echo "multiuser on" >> "$HOME/.screenrc"
      fi

      if ! grep -q "^acladd $(whoami)$" "$HOME/.screenrc"; then
        echo "Adding 'acladd $(whoami)' to ~/.screenrc..." | tee -a "$HOME/.claude-code.log"
        echo "acladd $(whoami)" >> "$HOME/.screenrc"
      fi
      export LANG=en_US.UTF-8
      export LC_ALL=en_US.UTF-8

      screen -U -dmS claude-code bash -c '
        cd ${var.folder}
        claude --dangerously-skip-permissions "$CODER_MCP_CLAUDE_TASK_PROMPT" | tee -a "$HOME/.claude-code.log"
        exec bash
      '
    else
      # Check if claude is installed before running
      if ! command_exists claude; then
        echo "Error: Claude Code is not installed. Please enable install_claude_code or install it manually."
        exit 1
      fi
    fi
    EOT
  run_on_start = true
}

resource "coder_app" "claude_code_web" {
  slug         = "claude-code-web"
  display_name = "Claude Code Web"
  agent_id     = var.agent_id
  url          = "http://localhost:3284/"
  icon         = var.icon
  subdomain    = true
}

resource "coder_app" "claude_code" {
  slug         = "claude-code"
  display_name = "Claude Code"
  agent_id     = var.agent_id
  command      = <<-EOT
    #!/bin/bash
    set -e

    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

    if [ "${var.experiment_use_tmux}" = "true" ]; then

      if ! tmux has-session -t claude-code-agentapi 2>/dev/null; then
        echo "Starting a new Claude Code agentapi tmux session." | tee -a "$HOME/.claude-code.log"
        # use low width to fit in the tasks UI sidebar. height is adjusted to ~match the default 80k (80x1000) characters
        # visible in the terminal screen.
        tmux new-session -d -s claude-code-agentapi -c ${var.folder} 'agentapi server --term-width 56 --term-height 1425 -- bash -c "claude --dangerously-skip-permissions | tee -a \"$HOME/.claude-code.log\""; exec bash'
      fi

      if tmux has-session -t claude-code 2>/dev/null; then
        echo "Attaching to existing Claude Code tmux session." | tee -a "$HOME/.claude-code.log"
        tmux attach-session -t claude-code
      else
        echo "Starting a new Claude Code tmux session." | tee -a "$HOME/.claude-code.log"
        tmux new-session -s claude-code -c ${var.folder} "claude --dangerously-skip-permissions | tee -a \"$HOME/.claude-code.log\"; exec bash"
      fi
    elif [ "${var.experiment_use_screen}" = "true" ]; then
      if screen -list | grep -q "claude-code"; then
        echo "Attaching to existing Claude Code screen session." | tee -a "$HOME/.claude-code.log"
        screen -xRR claude-code
      else
        echo "Starting a new Claude Code screen session." | tee -a "$HOME/.claude-code.log"
        screen -S claude-code bash -c 'claude --dangerously-skip-permissions | tee -a "$HOME/.claude-code.log"; exec bash'
      fi
    else
      cd ${var.folder}
      claude
    fi
    EOT
  icon         = var.icon
  order        = var.order
  group        = var.group
}
