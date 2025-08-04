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
  default     = "/icon/amazon-q.svg"
}

variable "folder" {
  type        = string
  description = "The folder to run Amazon Q in."
  default     = "/home/coder"
}

variable "install_amazon_q" {
  type        = bool
  description = "Whether to install Amazon Q."
  default     = true
}

variable "amazon_q_version" {
  type        = string
  description = "The version of Amazon Q to install."
  default     = "latest"
}

variable "experiment_use_screen" {
  type        = bool
  description = "Whether to use screen for running Amazon Q in the background."
  default     = false
}

variable "experiment_use_tmux" {
  type        = bool
  description = "Whether to use tmux instead of screen for running Amazon Q in the background."
  default     = false
}

variable "experiment_report_tasks" {
  type        = bool
  description = "Whether to enable task reporting."
  default     = true
}

variable "experiment_pre_install_script" {
  type        = string
  description = "Custom script to run before installing Amazon Q."
  default     = null
}

variable "experiment_post_install_script" {
  type        = string
  description = "Custom script to run after installing Amazon Q."
  default     = null
}

variable "experiment_auth_tarball" {
  type        = string
  description = "Base64 encoded, zstd compressed tarball of a pre-authenticated ~/.local/share/amazon-q directory. After running `q login` on another machine, you may generate it with: `cd ~/.local/share/amazon-q && tar -c . | zstd | base64 -w 0`"
  default     = "tarball"
}

variable "system_prompt" {
  type        = string
  description = "The system prompt to use for Amazon Q. This should instruct the agent how to do task reporting."
  default     = <<-EOT
    You are a helpful Coding assistant. Aim to autonomously investigate
    and solve issues the user gives you and test your work, whenever possible.
    Avoid shortcuts like mocking tests. When you get stuck, you can ask the user
    but opt for autonomy.

    YOU MUST REPORT ALL TASKS TO CODER.
    When reporting tasks, you MUST follow these EXACT instructions:
    - IMMEDIATELY report status after receiving ANY user message.
    - Be granular. If you are investigating with multiple steps, report each step to coder.

    Task state MUST be one of the following:
    - Use "state": "working" when actively processing WITHOUT needing additional user input.
    - Use "state": "complete" only when finished with a task.
    - Use "state": "failure" when you need ANY user input, lack sufficient details, or encounter blockers.

    Task summaries MUST:
    - Include specifics about what you're doing.
    - Include clear and actionable steps for the user.
    - Be less than 160 characters in length.
  EOT
}

variable "ai_prompt" {
  type        = string
  description = "The initial task prompt to send to Amazon Q."
  default     = "Please help me with my coding tasks. I'll provide specific instructions as needed."
}

locals {
  encoded_pre_install_script  = var.experiment_pre_install_script != null ? base64encode(var.experiment_pre_install_script) : ""
  encoded_post_install_script = var.experiment_post_install_script != null ? base64encode(var.experiment_post_install_script) : ""

    ${var.system_prompt}

    Your first task is:

    ${var.ai_prompt}
  EOT
  
  module_dir_name = ".amazon-q-module"
}

module "agentapi" {
  source  = "registry.coder.com/coder/agentapi/coder"
  version = "1.0.0"

  agent_id             = var.agent_id
  web_app_slug         = "amazon-q"
  web_app_order        = var.order
  web_app_group        = var.group
  web_app_icon         = var.icon 
  web_app_display_name = "Amazon Q"
  cli_app             = true
  cli_app_slug        = "amazon-q-cli"
  cli_app_display_name = "Amazon Q CLI"
  module_dir_name      = local.module_dir_name
  install_agentapi     = true
}

resource "coder_script" "amazon_q" {
  agent_id     = var.agent_id
  display_name = "Amazon Q"
  icon         = var.icon
  script       = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    command_exists() {
      command -v "$1" >/dev/null 2>&1
    }

    if [ -n "${local.encoded_pre_install_script}" ]; then
      echo "Running pre-install script..."
      echo "${local.encoded_pre_install_script}" | base64 -d > /tmp/pre_install.sh
      chmod +x /tmp/pre_install.sh
      /tmp/pre_install.sh
    fi

    if [ "${var.install_amazon_q}" = "true" ]; then
      echo "Installing Amazon Q..."
      PREV_DIR="$PWD"
      TMP_DIR="$(mktemp -d)"
      cd "$TMP_DIR"

      ARCH="$(uname -m)"
      case "$ARCH" in
        "x86_64")
          Q_URL="https://desktop-release.q.us-east-1.amazonaws.com/${var.amazon_q_version}/q-x86_64-linux.zip"
          ;;
        "aarch64"|"arm64")
          Q_URL="https://desktop-release.codewhisperer.us-east-1.amazonaws.com/${var.amazon_q_version}/q-aarch64-linux.zip"
          ;;
        *)
          echo "Error: Unsupported architecture: $ARCH. Amazon Q only supports x86_64 and arm64."
          exit 1
          ;;
      esac

      echo "Downloading Amazon Q for $ARCH..."
      curl --proto '=https' --tlsv1.2 -sSf "$Q_URL" -o "q.zip"
      unzip q.zip
      ./q/install.sh --no-confirm
      cd "$PREV_DIR"
      export PATH="$PATH:$HOME/.local/bin"
      echo "Installed Amazon Q version: $(q --version)"
    fi

    echo "Extracting auth tarball..."
    PREV_DIR="$PWD"
    echo "${var.experiment_auth_tarball}" | base64 -d > /tmp/auth.tar.zst
    rm -rf ~/.local/share/amazon-q
    mkdir -p ~/.local/share/amazon-q
    cd ~/.local/share/amazon-q
    tar -I zstd -xf /tmp/auth.tar.zst
    rm /tmp/auth.tar.zst
    cd "$PREV_DIR"
    echo "Extracted auth tarball"

    if [ "${var.experiment_report_tasks}" = "true" ]; then
      echo "Configuring Amazon Q to report tasks via Coder MCP..."
      q mcp add --name coder --command "coder" --args "exp,mcp,server,--allowed-tools,coder_report_task" --env "CODER_MCP_APP_STATUS_SLUG=amazon-q" --scope global --force
      echo "Added Coder MCP server to Amazon Q configuration"
    fi

    if [ -n "${local.encoded_post_install_script}" ]; then
      echo "Running post-install script..."
      echo "${local.encoded_post_install_script}" | base64 -d > /tmp/post_install.sh
      chmod +x /tmp/post_install.sh
      /tmp/post_install.sh
    fi


      exit 1
    fi

    if [ -n "${local.full_prompt}" ]; then
      mkdir -p "${HOME}/${local.module_dir_name}"
      echo "${local.full_prompt}" > "${HOME}/${local.module_dir_name}/prompt.txt"
      Q_ARGS=(chat --trust-all-tools --message "$(cat ${HOME}/${local.module_dir_name}/prompt.txt)")
    else
      echo "Starting without a prompt"
      Q_ARGS=(chat --trust-all-tools)
    fi

    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

    cd "${var.folder}"
    agentapi server --term-width 67 --term-height 1190 -- \
        bash -c "$(printf '%q ' "q" "${Q_ARGS[@]}")"
    EOT
  run_on_start = true
}

resource "coder_ai_task" "amazon_q" {
  sidebar_app {
    id = module.agentapi.web_app_id
  }
}
    set -e

    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8

    if [ "${var.experiment_use_tmux}" = "true" ]; then
      if tmux has-session -t amazon-q 2>/dev/null; then
        echo "Attaching to existing Amazon Q tmux session." | tee -a "$HOME/.amazon-q.log"
        tmux attach-session -t amazon-q
      else
        echo "Starting a new Amazon Q tmux session." | tee -a "$HOME/.amazon-q.log"
        tmux new-session -s amazon-q -c ${var.folder} "q chat --trust-all-tools | tee -a \"$HOME/.amazon-q.log\"; exec bash"
      fi
    elif [ "${var.experiment_use_screen}" = "true" ]; then
      if screen -list | grep -q "amazon-q"; then
        echo "Attaching to existing Amazon Q screen session." | tee -a "$HOME/.amazon-q.log"
        screen -xRR amazon-q
      else
        echo "Starting a new Amazon Q screen session." | tee -a "$HOME/.amazon-q.log"
        screen -S amazon-q bash -c 'q chat --trust-all-tools | tee -a "$HOME/.amazon-q.log"; exec bash'
      fi
    else
      cd ${var.folder}
      q chat --trust-all-tools
    fi
    EOT
  icon         = var.icon
  order        = var.order
  group        = var.group
}
