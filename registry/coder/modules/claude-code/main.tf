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
  default     = "v0.2.2"
}

locals {
  # we have to trim the slash because otherwise coder exp mcp will
  # set up an invalid claude config 
  workdir                                = trimsuffix(var.folder, "/")
  encoded_pre_install_script             = var.experiment_pre_install_script != null ? base64encode(var.experiment_pre_install_script) : ""
  encoded_post_install_script            = var.experiment_post_install_script != null ? base64encode(var.experiment_post_install_script) : ""
  agentapi_start_command                 = <<-EOT
    #!/bin/bash
    set -e
    
    # if the first argument is not empty, start claude with the prompt
    if [ -n "$1" ]; then
      prompt="$(cat ~/.claude-code-prompt)"
      cp ~/.claude-code-prompt /tmp/claude-code-prompt
    else
      rm -f /tmp/claude-code-prompt
    fi

    # We need to check if there's a session to use --continue. If there's no session,
    # using this flag would cause claude to exit with an error.
    # warning: this is a hack and will break if claude changes the format of the .claude.json file.
    # Also, this solution is not ideal: a user has to quit claude in order for the session id to appear
    # in .claude.json. If they just restart the workspace, the session id will not be available.
    continue_flag=""
    if grep -q '"lastSessionId":' ~/.claude.json; then
      echo "Found a Claude Code session to continue."
      continue_flag="--continue"
    else
      echo "No Claude Code session to continue."
    fi

    # use low width to fit in the tasks UI sidebar. height is adjusted so that width x height ~= 80x1000 characters
    # visible in the terminal screen by default.
    prompt_subshell='"$(cat /tmp/claude-code-prompt)"'
    agentapi server --term-width 67 --term-height 1190 -- bash -c "claude $continue_flag --dangerously-skip-permissions $prompt_subshell"
  EOT
  agentapi_wait_for_start_command        = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

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
  EOT
  agentapi_start_command_base64          = base64encode(local.agentapi_start_command)
  agentapi_wait_for_start_command_base64 = base64encode(local.agentapi_wait_for_start_command)
}

# Install and Initialize Claude Code
resource "coder_script" "claude_code" {
  agent_id     = var.agent_id
  display_name = "Claude Code"
  icon         = var.icon
  script       = <<-EOT
    #!/bin/bash
    set -e

    command_exists() {
      command -v "$1" >/dev/null 2>&1
    }

    if [ ! -d "${local.workdir}" ]; then
      echo "Warning: The specified folder '${local.workdir}' does not exist."
      echo "Creating the folder..."
      # The folder must exist before tmux is started or else claude will start
      # in the home directory.
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
      wget "https://github.com/coder/agentapi/releases/download/${var.agentapi_version}/$binary_name"
      chmod +x "$binary_name"
      sudo mv "$binary_name" /usr/local/bin/agentapi
    fi
    if ! command_exists agentapi; then
      echo "Error: AgentAPI is not installed. Please enable install_agentapi or install it manually."
      exit 1
    fi

    # save the prompt for the agentapi start command
    echo -n "$CODER_MCP_CLAUDE_TASK_PROMPT" > ~/.claude-code-prompt

    echo -n "${local.agentapi_start_command_base64}" | base64 -d > ~/.agentapi-start-command
    chmod +x ~/.agentapi-start-command
    echo -n "${local.agentapi_wait_for_start_command_base64}" | base64 -d > ~/.agentapi-wait-for-start-command
    chmod +x ~/.agentapi-wait-for-start-command

    if [ "${var.experiment_report_tasks}" = "true" ]; then
      echo "Configuring Claude Code to report tasks via Coder MCP..."
      coder exp mcp configure claude-code ${local.workdir} --ai-agentapi-url http://localhost:3284
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

    echo "Running Claude Code in the background..."
    if ! command_exists screen; then
      echo "Error: screen is not installed. Please install screen manually."
      exit 1
    fi

    touch "$HOME/.claude-code.log"
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

    screen -U -dmS agentapi-cc bash -c '
      cd ${local.workdir}
      # setting the first argument will make claude use the prompt
      ~/.agentapi-start-command true
      exec bash
    '
    ~/.agentapi-wait-for-start-command
    EOT
  run_on_start = true
}

resource "coder_app" "claude_code_web" {
  # use a short slug to mitigate https://github.com/coder/coder/issues/15178
  slug         = "ccw"
  display_name = "Claude Code Web"
  agent_id     = var.agent_id
  url          = "http://localhost:3284/"
  icon         = var.icon
  subdomain    = true
  healthcheck {
    url       = "http://localhost:3284/status"
    interval  = 6
    threshold = 10
  }
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

    if ! screen -list | grep -q "agentapi-cc"; then
      screen -S agentapi-cc bash -c '
        cd ${local.workdir}
        # start agentapi without claude using the prompt (no argument)
        ~/.agentapi-start-command
        exec bash
      '
    fi

    agentapi attach
    EOT
  icon         = var.icon
  order        = var.order
  group        = var.group
}

resource "coder_ai_task" "claude_code" {
  sidebar_app {
    id = coder_app.claude_code_web.id
  }
}
