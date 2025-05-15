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
  default     = "/icon/aider.svg"
}

variable "folder" {
  type        = string
  description = "The folder to run Aider in."
  default     = "/home/coder"
}

variable "install_aider" {
  type        = bool
  description = "Whether to install Aider."
  default     = true
}

variable "aider_version" {
  type        = string
  description = "The version of Aider to install."
  default     = "latest"
}

variable "use_screen" {
  type        = bool
  description = "Whether to use screen for running Aider in the background"
  default     = true
}

variable "use_tmux" {
  type        = bool
  description = "Whether to use tmux instead of screen for running Aider in the background"
  default     = false
}

variable "session_name" {
  type        = string
  description = "Name for the persistent session (screen or tmux)"
  default     = "aider"
}

variable "experiment_report_tasks" {
  type        = bool
  description = "Whether to enable task reporting."
  default     = true
}

variable "system_prompt" {
  type        = string
  description = "System prompt for instructing Aider on task reporting and behavior"
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

variable "task_prompt" {
  type        = string
  description = "Task prompt to use with Aider"
  default     = ""
}

variable "experiment_pre_install_script" {
  type        = string
  description = "Custom script to run before installing Aider."
  default     = null
}

variable "experiment_post_install_script" {
  type        = string
  description = "Custom script to run after installing Aider."
  default     = null
}

variable "experiment_additional_extensions" {
  type        = string
  description = "Additional extensions configuration in YAML format to append to the config."
  default     = null
}

variable "ai_provider" {
  type        = string
  description = "AI provider to use with Aider (openai, anthropic, azure, google, etc.)"
  default     = "anthropic"
  validation {
    condition     = contains(["openai", "anthropic", "azure", "google", "cohere", "mistral", "ollama", "custom"], var.ai_provider)
    error_message = "ai_provider must be one of: openai, anthropic, azure, google, cohere, mistral, ollama, custom"
  }
}

variable "ai_model" {
  type        = string
  description = "AI model to use with Aider. Can use Aider's built-in aliases like '4o' (gpt-4o), 'sonnet' (claude-3-7-sonnet), 'opus' (claude-3-opus), etc."
  default     = "sonnet"
}

variable "ai_api_key" {
  type        = string
  description = "API key for the selected AI provider. This will be set as the appropriate environment variable based on the provider."
  default     = ""
  sensitive   = true
}

variable "custom_env_var_name" {
  type        = string
  description = "Custom environment variable name when using custom provider"
  default     = ""
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
    CODER_MCP_APP_STATUS_SLUG: aider
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

  formatted_base        = "  ${replace(trimspace(local.base_extensions), "\n", "\n  ")}"
  additional_extensions = var.experiment_additional_extensions != null ? "\n  ${replace(trimspace(var.experiment_additional_extensions), "\n", "\n  ")}" : ""

  combined_extensions = <<-EOT
extensions:
${local.formatted_base}${local.additional_extensions}
EOT

  encoded_pre_install_script  = var.experiment_pre_install_script != null ? base64encode(var.experiment_pre_install_script) : ""
  encoded_post_install_script = var.experiment_post_install_script != null ? base64encode(var.experiment_post_install_script) : ""

  # Combine system prompt and task prompt for aider
  combined_prompt = trimspace(<<-EOT
SYSTEM PROMPT:
${var.system_prompt}

This is your current task: ${var.task_prompt}
EOT
  )

  # Map providers to their environment variable names
  provider_env_vars = {
    openai    = "OPENAI_API_KEY"
    anthropic = "ANTHROPIC_API_KEY"
    azure     = "AZURE_OPENAI_API_KEY"
    google    = "GOOGLE_API_KEY"
    cohere    = "COHERE_API_KEY"
    mistral   = "MISTRAL_API_KEY"
    ollama    = "OLLAMA_HOST"
    custom    = var.custom_env_var_name
  }

  # Get the environment variable name for selected provider
  env_var_name = local.provider_env_vars[var.ai_provider]

  # Model flag for aider command
  model_flag = var.ai_provider == "ollama" ? "--ollama-model" : "--model"
}

# Install and Initialize Aider
resource "coder_script" "aider" {
  agent_id     = var.agent_id
  display_name = "Aider"
  icon         = var.icon
  script       = <<-EOT
    #!/bin/bash
    set -e

    command_exists() {
      command -v "$1" >/dev/null 2>&1
    }

    echo "Setting up Aider AI pair programming..."
    
    if [ "${var.use_screen}" = "true" ] && [ "${var.use_tmux}" = "true" ]; then
      echo "Error: Both use_screen and use_tmux cannot be enabled at the same time."
      exit 1
    fi
    
    mkdir -p "${var.folder}"

    if [ "$(uname)" = "Linux" ]; then
      echo "Checking dependencies for Linux..."
      
      if [ "${var.use_tmux}" = "true" ]; then
        if ! command_exists tmux; then
          echo "Installing tmux for persistent sessions..."
          if command -v apt-get >/dev/null 2>&1; then
            if command -v sudo >/dev/null 2>&1; then
              sudo apt-get update -qq
              sudo apt-get install -y -qq tmux
            else
              apt-get update -qq || echo "Warning: Cannot update package lists without sudo privileges"
              apt-get install -y -qq tmux || echo "Warning: Cannot install tmux without sudo privileges"
            fi
          elif command -v dnf >/dev/null 2>&1; then
            if command -v sudo >/dev/null 2>&1; then
              sudo dnf install -y -q tmux
            else
              dnf install -y -q tmux || echo "Warning: Cannot install tmux without sudo privileges"
            fi
          else
            echo "Warning: Unable to install tmux on this system. Neither apt-get nor dnf found."
          fi
        else
          echo "tmux is already installed, skipping installation."
        fi
      elif [ "${var.use_screen}" = "true" ]; then
        if ! command_exists screen; then
          echo "Installing screen for persistent sessions..."
          if command -v apt-get >/dev/null 2>&1; then
            if command -v sudo >/dev/null 2>&1; then
              sudo apt-get update -qq
              sudo apt-get install -y -qq screen
            else
              apt-get update -qq || echo "Warning: Cannot update package lists without sudo privileges"
              apt-get install -y -qq screen || echo "Warning: Cannot install screen without sudo privileges"
            fi
          elif command -v dnf >/dev/null 2>&1; then
            if command -v sudo >/dev/null 2>&1; then
              sudo dnf install -y -q screen
            else
              dnf install -y -q screen || echo "Warning: Cannot install screen without sudo privileges"
            fi
          else
            echo "Warning: Unable to install screen on this system. Neither apt-get nor dnf found."
          fi
        else
          echo "screen is already installed, skipping installation."
        fi
      fi
    else
      echo "This module currently only supports Linux workspaces."
      exit 1
    fi

    if [ -n "${local.encoded_pre_install_script}" ]; then
      echo "Running pre-install script..."
      echo "${local.encoded_pre_install_script}" | base64 -d > /tmp/pre_install.sh
      chmod +x /tmp/pre_install.sh
      /tmp/pre_install.sh
    fi

    if [ "${var.install_aider}" = "true" ]; then
      echo "Installing Aider..."
      
      if ! command_exists python3 || ! command_exists pip3; then
        echo "Installing Python dependencies required for Aider..."
        if command -v apt-get >/dev/null 2>&1; then
          if command -v sudo >/dev/null 2>&1; then
            sudo apt-get update -qq
            sudo apt-get install -y -qq python3-pip python3-venv
          else
            apt-get update -qq || echo "Warning: Cannot update package lists without sudo privileges"
            apt-get install -y -qq python3-pip python3-venv || echo "Warning: Cannot install Python packages without sudo privileges"
          fi
        elif command -v dnf >/dev/null 2>&1; then
          if command -v sudo >/dev/null 2>&1; then
            sudo dnf install -y -q python3-pip python3-virtualenv
          else
            dnf install -y -q python3-pip python3-virtualenv || echo "Warning: Cannot install Python packages without sudo privileges"
          fi
        else
          echo "Warning: Unable to install Python on this system. Neither apt-get nor dnf found."
        fi
      else
        echo "Python is already installed, skipping installation."
      fi
      
      if ! command_exists aider; then
        curl -LsSf https://aider.chat/install.sh | sh
      fi
      
      if [ -f "$HOME/.bashrc" ]; then
        if ! grep -q 'export PATH="$HOME/bin:$PATH"' "$HOME/.bashrc"; then
          echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
        fi
      fi
      
      if [ -f "$HOME/.zshrc" ]; then
        if ! grep -q 'export PATH="$HOME/bin:$PATH"' "$HOME/.zshrc"; then
          echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.zshrc"
        fi
      fi
      
    fi
    
    if [ -n "${local.encoded_post_install_script}" ]; then
      echo "Running post-install script..."
      echo "${local.encoded_post_install_script}" | base64 -d > /tmp/post_install.sh
      chmod +x /tmp/post_install.sh
      /tmp/post_install.sh
    fi
    
    if [ "${var.experiment_report_tasks}" = "true" ]; then
      echo "Configuring Aider to report tasks via Coder MCP..."
      
      mkdir -p "$HOME/.config/aider"
      
      cat > "$HOME/.config/aider/config.yml" << EOL
${trimspace(local.combined_extensions)}
EOL
      echo "Added Coder MCP extension to Aider config.yml"
    fi

    echo "Starting persistent Aider session..."
    
    touch "$HOME/.aider.log"
    
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    
    export PATH="$HOME/bin:$PATH"
    
    if [ "${var.use_tmux}" = "true" ]; then
      if [ -n "${var.task_prompt}" ]; then
        echo "Running Aider with message in tmux session..."
        
        # Configure tmux for shared sessions
        if [ ! -f "$HOME/.tmux.conf" ]; then
          echo "Creating ~/.tmux.conf with shared session settings..."
          echo "set -g mouse on" > "$HOME/.tmux.conf"
        fi
        
        if ! grep -q "^set -g mouse on$" "$HOME/.tmux.conf"; then
          echo "Adding 'set -g mouse on' to ~/.tmux.conf..."
          echo "set -g mouse on" >> "$HOME/.tmux.conf"
        fi
        
        echo "Starting Aider using ${var.ai_provider} provider and model: ${var.ai_model}"
        tmux new-session -d -s ${var.session_name} -c ${var.folder} "export ${local.env_var_name}=\"${var.ai_api_key}\"; aider --architect --yes-always ${local.model_flag} ${var.ai_model} --message \"${local.combined_prompt}\""
        echo "Aider task started in tmux session '${var.session_name}'. Check the UI for progress."
      else
        # Configure tmux for shared sessions
        if [ ! -f "$HOME/.tmux.conf" ]; then
          echo "Creating ~/.tmux.conf with shared session settings..."
          echo "set -g mouse on" > "$HOME/.tmux.conf"
        fi
        
        if ! grep -q "^set -g mouse on$" "$HOME/.tmux.conf"; then
          echo "Adding 'set -g mouse on' to ~/.tmux.conf..."
          echo "set -g mouse on" >> "$HOME/.tmux.conf"
        fi
        
        echo "Starting Aider using ${var.ai_provider} provider and model: ${var.ai_model}"
        tmux new-session -d -s ${var.session_name} -c ${var.folder} "export ${local.env_var_name}=\"${var.ai_api_key}\"; aider --architect --yes-always ${local.model_flag} ${var.ai_model} --message \"${var.system_prompt}\""
        echo "Tmux session '${var.session_name}' started. Access it by clicking the Aider button."
      fi
    else
      if [ -n "${var.task_prompt}" ]; then
        echo "Running Aider with message in screen session..."
        
        if [ ! -f "$HOME/.screenrc" ]; then
          echo "Creating ~/.screenrc and adding multiuser settings..."
          echo -e "multiuser on\nacladd $(whoami)" > "$HOME/.screenrc"
        fi
        
        if ! grep -q "^multiuser on$" "$HOME/.screenrc"; then
          echo "Adding 'multiuser on' to ~/.screenrc..."
          echo "multiuser on" >> "$HOME/.screenrc"
        fi

        if ! grep -q "^acladd $(whoami)$" "$HOME/.screenrc"; then
          echo "Adding 'acladd $(whoami)' to ~/.screenrc..."
          echo "acladd $(whoami)" >> "$HOME/.screenrc"
        fi
        
        echo "Starting Aider using ${var.ai_provider} provider and model: ${var.ai_model}"
        screen -U -dmS ${var.session_name} bash -c "
          cd ${var.folder}
          export PATH=\"$HOME/bin:$HOME/.local/bin:$PATH\"
          export ${local.env_var_name}=\"${var.ai_api_key}\"
          aider --architect --yes-always ${local.model_flag} ${var.ai_model} --message \"${local.combined_prompt}\"
          /bin/bash
        "
        
        echo "Aider task started in screen session '${var.session_name}'. Check the UI for progress."
      else
        
        if [ ! -f "$HOME/.screenrc" ]; then
          echo "Creating ~/.screenrc and adding multiuser settings..."
          echo -e "multiuser on\nacladd $(whoami)" > "$HOME/.screenrc"
        fi
        
        if ! grep -q "^multiuser on$" "$HOME/.screenrc"; then
          echo "Adding 'multiuser on' to ~/.screenrc..."
          echo "multiuser on" >> "$HOME/.screenrc"
        fi

        if ! grep -q "^acladd $(whoami)$" "$HOME/.screenrc"; then
          echo "Adding 'acladd $(whoami)' to ~/.screenrc..."
          echo "acladd $(whoami)" >> "$HOME/.screenrc"
        fi
        
        echo "Starting Aider using ${var.ai_provider} provider and model: ${var.ai_model}"
        screen -U -dmS ${var.session_name} bash -c "
          cd ${var.folder}
          export PATH=\"$HOME/bin:$HOME/.local/bin:$PATH\"
          export ${local.env_var_name}=\"${var.ai_api_key}\"
          aider --architect --yes-always ${local.model_flag} ${var.ai_model} --message \"${local.combined_prompt}\"
          /bin/bash
        "
        echo "Screen session '${var.session_name}' started. Access it by clicking the Aider button."
      fi
    fi
    
    echo "Aider setup complete!"
  EOT
  run_on_start = true
}

# Aider CLI app
resource "coder_app" "aider_cli" {
  agent_id     = var.agent_id
  slug         = "aider"
  display_name = "Aider"
  icon         = var.icon
  command      = <<-EOT
    #!/bin/bash
    set -e
    
    export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
    
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    
    if [ "${var.use_tmux}" = "true" ]; then
      if tmux has-session -t ${var.session_name} 2>/dev/null; then
        echo "Attaching to existing Aider tmux session..."
        tmux attach-session -t ${var.session_name}
      else
        echo "Starting new Aider tmux session..."
        tmux new-session -s ${var.session_name} -c ${var.folder} "export ${local.env_var_name}=\"${var.ai_api_key}\"; aider ${local.model_flag} ${var.ai_model} --message \"${local.combined_prompt}\"; exec bash"
      fi
    elif [ "${var.use_screen}" = "true" ]; then
      if ! screen -list | grep -q "${var.session_name}"; then
        echo "Error: No existing Aider session found. Please wait for the script to start it."
        exit 1
      fi
      screen -xRR ${var.session_name}
    else
      cd "${var.folder}"
      echo "Starting Aider directly..."
      export ${local.env_var_name}="${var.ai_api_key}"
      aider ${local.model_flag} ${var.ai_model} --message "${local.combined_prompt}"
    fi
  EOT
  order        = var.order
}
