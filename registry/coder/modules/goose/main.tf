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
  default     = "/icon/goose.svg"
}

variable "folder" {
  type        = string
  description = "The folder to run Goose in."
  default     = "/home/coder"
}

variable "install_goose" {
  type        = bool
  description = "Whether to install Goose."
  default     = true
}

variable "goose_version" {
  type        = string
  description = "The version of Goose to install."
  default     = "stable"
}

variable "experiment_use_screen" {
  type        = bool
  description = "Whether to use screen for running Goose in the background."
  default     = false
}

variable "experiment_use_tmux" {
  type        = bool
  description = "Whether to use tmux instead of screen for running Goose in the background."
  default     = false
}

variable "session_name" {
  type        = string
  description = "Name for the persistent session (screen or tmux)"
  default     = "goose"
}

variable "experiment_report_tasks" {
  type        = bool
  description = "Whether to enable task reporting."
  default     = false
}

variable "experiment_auto_configure" {
  type        = bool
  description = "Whether to automatically configure Goose."
  default     = false
}

variable "experiment_goose_provider" {
  type        = string
  description = "The provider to use for Goose (e.g., anthropic)."
  default     = ""
}

variable "experiment_goose_model" {
  type        = string
  description = "The model to use for Goose (e.g., claude-3-5-sonnet-latest)."
  default     = ""
}

variable "experiment_pre_install_script" {
  type        = string
  description = "Custom script to run before installing Goose."
  default     = null
}

variable "experiment_post_install_script" {
  type        = string
  description = "Custom script to run after installing Goose."
  default     = null
}

variable "experiment_additional_extensions" {
  type        = string
  description = "Additional extensions configuration in YAML format to append to the config."
  default     = null
}

locals {
  base_extensions = <<-EOT
coder:
  args:
  - exp
  - mcp
  - server
  cmd: coder
  description: Report ALL tasks and statuses (in progress, done, failed) you are working on.
  enabled: true
  envs:
    CODER_MCP_APP_STATUS_SLUG: goose
  name: Coder
  timeout: 3000
  type: stdio
developer:
  display_name: Developer
  enabled: true
  name: developer
  timeout: 300
  type: builtin
EOT

  # Add two spaces to each line of extensions to match YAML structure
  formatted_base        = "  ${replace(trimspace(local.base_extensions), "\n", "\n  ")}"
  additional_extensions = var.experiment_additional_extensions != null ? "\n  ${replace(trimspace(var.experiment_additional_extensions), "\n", "\n  ")}" : ""

  combined_extensions = <<-EOT
extensions:
${local.formatted_base}${local.additional_extensions}
EOT

  encoded_pre_install_script  = var.experiment_pre_install_script != null ? base64encode(var.experiment_pre_install_script) : ""
  encoded_post_install_script = var.experiment_post_install_script != null ? base64encode(var.experiment_post_install_script) : ""
}

# Install and Initialize Goose
resource "coder_script" "goose" {
  agent_id     = var.agent_id
  display_name = "Goose"
  icon         = var.icon
  script       = <<-EOT
    #!/bin/bash
    set -e

    # Function to check if a command exists
    command_exists() {
      command -v "$1" >/dev/null 2>&1
    }

    # Run pre-install script if provided
    if [ -n "${local.encoded_pre_install_script}" ]; then
      echo "Running pre-install script..."
      echo "${local.encoded_pre_install_script}" | base64 -d > /tmp/pre_install.sh
      chmod +x /tmp/pre_install.sh
      /tmp/pre_install.sh
    fi

    # Install Goose if enabled
    if [ "${var.install_goose}" = "true" ]; then
      if ! command_exists npm; then
        echo "Error: npm is not installed. Please install Node.js and npm first."
        exit 1
      fi
      echo "Installing Goose..."
      RELEASE_TAG=v${var.goose_version} curl -fsSL https://github.com/block/goose/releases/download/stable/download_cli.sh | CONFIGURE=false bash
    fi

    # Run post-install script if provided
    if [ -n "${local.encoded_post_install_script}" ]; then
      echo "Running post-install script..."
      echo "${local.encoded_post_install_script}" | base64 -d > /tmp/post_install.sh
      chmod +x /tmp/post_install.sh
      /tmp/post_install.sh
    fi

    # Configure Goose if auto-configure is enabled
    if [ "${var.experiment_auto_configure}" = "true" ]; then
      echo "Configuring Goose..."
      mkdir -p "$HOME/.config/goose"
      cat > "$HOME/.config/goose/config.yaml" << EOL
GOOSE_PROVIDER: ${var.experiment_goose_provider}
GOOSE_MODEL: ${var.experiment_goose_model}
${trimspace(local.combined_extensions)}
EOL
    fi

    # Write system prompt to config
    mkdir -p "$HOME/.config/goose"
    echo "$GOOSE_SYSTEM_PROMPT" > "$HOME/.config/goose/.goosehints"

    # Handle terminal multiplexer selection (tmux or screen)
    if [ "${var.experiment_use_tmux}" = "true" ] && [ "${var.experiment_use_screen}" = "true" ]; then
      echo "Error: Both experiment_use_tmux and experiment_use_screen cannot be true simultaneously."
      echo "Please set only one of them to true."
      exit 1
    fi

    # Determine goose command
    if command_exists goose; then
      GOOSE_CMD=goose
    elif [ -f "$HOME/.local/bin/goose" ]; then
      GOOSE_CMD="$HOME/.local/bin/goose"
    else
      echo "Error: Goose is not installed. Please enable install_goose or install it manually."
      exit 1
    fi

    # Run with tmux if enabled
    if [ "${var.experiment_use_tmux}" = "true" ]; then
      echo "Running Goose in the background with tmux..."

      # Check if tmux is installed
      if ! command_exists tmux; then
        echo "Error: tmux is not installed. Please install tmux manually."
        exit 1
      fi

      touch "$HOME/.goose.log"

      export LANG=en_US.UTF-8
      export LC_ALL=en_US.UTF-8

      # Configure tmux for shared sessions
      if [ ! -f "$HOME/.tmux.conf" ]; then
        echo "Creating ~/.tmux.conf with shared session settings..."
        echo "set -g mouse on" > "$HOME/.tmux.conf"
      fi

      if ! grep -q "^set -g mouse on$" "$HOME/.tmux.conf"; then
        echo "Adding 'set -g mouse on' to ~/.tmux.conf..."
        echo "set -g mouse on" >> "$HOME/.tmux.conf"
      fi

      # Create a new tmux session in detached mode
      tmux new-session -d -s ${var.session_name} -c ${var.folder} "\"$GOOSE_CMD\" run --text \"Review your goosehints. Every step of the way, report tasks to Coder with proper descriptions and statuses. Your task at hand: $GOOSE_TASK_PROMPT\" --interactive | tee -a \"$HOME/.goose.log\"; exec bash"
    elif [ "${var.experiment_use_screen}" = "true" ]; then
      echo "Running Goose in the background..."

      # Check if screen is installed
      if ! command_exists screen; then
        echo "Error: screen is not installed. Please install screen manually."
        exit 1
      fi

      touch "$HOME/.goose.log"

      # Ensure the screenrc exists
      if [ ! -f "$HOME/.screenrc" ]; then
        echo "Creating ~/.screenrc and adding multiuser settings..." | tee -a "$HOME/.goose.log"
        echo -e "multiuser on\nacladd $(whoami)" > "$HOME/.screenrc"
      fi

      if ! grep -q "^multiuser on$" "$HOME/.screenrc"; then
        echo "Adding 'multiuser on' to ~/.screenrc..." | tee -a "$HOME/.goose.log"
        echo "multiuser on" >> "$HOME/.screenrc"
      fi

      if ! grep -q "^acladd $(whoami)$" "$HOME/.screenrc"; then
        echo "Adding 'acladd $(whoami)' to ~/.screenrc..." | tee -a "$HOME/.goose.log"
        echo "acladd $(whoami)" >> "$HOME/.screenrc"
      fi
      export LANG=en_US.UTF-8
      export LC_ALL=en_US.UTF-8

      screen -U -dmS ${var.session_name} bash -c "
        cd ${var.folder}
        \"$GOOSE_CMD\" run --text \"Review your goosehints. Every step of the way, report tasks to Coder with proper descriptions and statuses. Your task at hand: $GOOSE_TASK_PROMPT\" --interactive | tee -a \"$HOME/.goose.log\"
        /bin/bash
      "
    fi
    EOT
  run_on_start = true
}

resource "coder_app" "goose" {
  slug         = "goose"
  display_name = "Goose"
  agent_id     = var.agent_id
  command      = <<-EOT
    #!/bin/bash
    set -e

    # Function to check if a command exists
    command_exists() {
      command -v "$1" >/dev/null 2>&1
    }

    # Determine goose command
    if command_exists goose; then
      GOOSE_CMD=goose
    elif [ -f "$HOME/.local/bin/goose" ]; then
      GOOSE_CMD="$HOME/.local/bin/goose"
    else
      echo "Error: Goose is not installed. Please enable install_goose or install it manually."
      exit 1
    fi

    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

    if [ "${var.experiment_use_tmux}" = "true" ]; then
      if tmux has-session -t ${var.session_name} 2>/dev/null; then
        echo "Attaching to existing Goose tmux session." | tee -a "$HOME/.goose.log"
        tmux attach-session -t ${var.session_name}
      else
        echo "Starting a new Goose tmux session." | tee -a "$HOME/.goose.log"
        tmux new-session -s ${var.session_name} -c ${var.folder} "\"$GOOSE_CMD\" run --text \"Review your goosehints. Every step of the way, report tasks to Coder with proper descriptions and statuses. Your task at hand: $GOOSE_TASK_PROMPT\" --interactive | tee -a \"$HOME/.goose.log\"; exec bash"
      fi
    elif [ "${var.experiment_use_screen}" = "true" ]; then
      # Check if session exists first
      if ! screen -list | grep -q "${var.session_name}"; then
        echo "Error: No existing Goose session found. Please wait for the script to start it."
        exit 1
      fi
      # Only attach to existing session
      screen -xRR ${var.session_name}
    else
      cd ${var.folder}
      "$GOOSE_CMD" run --text "Review goosehints. Your task: $GOOSE_TASK_PROMPT" --interactive
    fi
    EOT
  icon         = var.icon
  order        = var.order
  group        = var.group
}
