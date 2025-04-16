terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.17"
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

variable "experiment_report_tasks" {
  type        = bool
  description = "Whether to enable task reporting."
  default     = false
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

    # Install Claude Code if enabled
    if [ "${var.install_claude_code}" = "true" ]; then
      if ! command_exists npm; then
        echo "Error: npm is not installed. Please install Node.js and npm first."
        exit 1
      fi
      echo "Installing Claude Code..."
      npm install -g @anthropic-ai/claude-code@${var.claude_code_version}
    fi

    if [ "${var.experiment_report_tasks}" = "true" ]; then
      echo "Configuring Claude Code to report tasks via Coder MCP..."
      coder exp mcp configure claude-code ${var.folder}
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
        claude --dangerously-skip-permissions | tee -a "$HOME/.claude-code.log"
        exec bash
      '
      # Extremely hacky way to send the prompt to the screen session
      # This will be fixed in the future, but `claude` was not sending MCP
      # tasks when an initial prompt is provided.
      screen -S claude-code -X stuff "$CODER_MCP_CLAUDE_TASK_PROMPT"
      sleep 5
      screen -S claude-code -X stuff "^M"
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

resource "coder_app" "claude_code" {
  slug         = "claude-code"
  display_name = "Claude Code"
  agent_id     = var.agent_id
  command      = <<-EOT
    #!/bin/bash
    set -e

    if [ "${var.experiment_use_screen}" = "true" ]; then
      if screen -list | grep -q "claude-code"; then
        export LANG=en_US.UTF-8
        export LC_ALL=en_US.UTF-8
        echo "Attaching to existing Claude Code session." | tee -a "$HOME/.claude-code.log"
        screen -xRR claude-code
      else
        echo "Starting a new Claude Code session." | tee -a "$HOME/.claude-code.log"
        screen -S claude-code bash -c 'export LANG=en_US.UTF-8; export LC_ALL=en_US.UTF-8; claude --dangerously-skip-permissions | tee -a "$HOME/.claude-code.log"; exec bash'
      fi
    else
      cd ${var.folder}
      export LANG=en_US.UTF-8
      export LC_ALL=en_US.UTF-8
      claude
    fi
    EOT
  icon         = var.icon
}
