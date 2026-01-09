terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.0"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "display_name" {
  type        = string
  description = "The display name for the Parsec application."
  default     = "Parsec"
}

variable "slug" {
  type        = string
  description = "The slug for the Parsec application."
  default     = "parsec"
}

variable "icon" {
  type        = string
  description = "The icon for the Parsec application."
  default     = "/icon/desktop.svg"
}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation."
  default     = null
}

variable "group" {
  type        = string
  description = "The name of a group that this app belongs to."
  default     = null
}

variable "headless" {
  type        = bool
  description = "Run Parsec in headless mode (without physical display)."
  default     = true
}

variable "auto_start" {
  type        = bool
  description = "Automatically start Parsec service on workspace start."
  default     = true
}

resource "coder_script" "parsec" {
  agent_id     = var.agent_id
  display_name = "Parsec Installation"
  icon         = var.icon

  script = <<-EOT
    #!/bin/bash
    set -e

    echo "=== Installing Parsec ==="
    
    # Check if Parsec is already installed
    if command -v parsecd &> /dev/null; then
      echo "Parsec is already installed"
    else
      echo "Downloading and installing Parsec..."
      
      # Detect architecture
      ARCH=$(uname -m)
      case $ARCH in
        x86_64)
          PARSEC_URL="https://builds.parsec.app/package/parsec-linux.deb"
          ;;
        aarch64)
          echo "ARM64 architecture detected, using alternative package"
          PARSEC_URL="https://builds.parsec.app/package/parsec-linux.deb"
          ;;
        *)
          echo "Unsupported architecture: $ARCH"
          exit 1
          ;;
      esac
      
      # Download Parsec
      cd /tmp
      curl -fsSL -o parsec-linux.deb "$PARSEC_URL"
      
      # Install Parsec
      if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y ./parsec-linux.deb
      elif command -v dpkg &> /dev/null; then
        sudo dpkg -i parsec-linux.deb || sudo apt-get install -f -y
      else
        echo "Unsupported package manager. Please install Parsec manually."
        exit 1
      fi
      
      rm -f parsec-linux.deb
      echo "Parsec installed successfully"
    fi

    # Configure headless mode if enabled
    if [ "${var.headless}" = "true" ]; then
      echo "Configuring headless mode..."
      mkdir -p ~/.parsec
      
      # Create config for headless operation
      cat > ~/.parsec/config.txt <<EOF
# Parsec headless configuration
host_virtual_monitor = true
host_privacy_mode = true
EOF
    fi

    # Start Parsec service if auto_start is enabled
    if [ "${var.auto_start}" = "true" ]; then
      echo "Starting Parsec service..."
      
      # Start parsecd in background
      if command -v parsecd &> /dev/null; then
        nohup parsecd app_daemon=1 &> /tmp/parsec.log &
        echo "Parsec daemon started"
      else
        echo "Warning: parsecd not found in PATH"
      fi
    fi

    echo "=== Parsec setup complete ==="
    echo "Open the Parsec app on your local machine to connect"
    echo "You will need to log in with your Parsec account"
  EOT

  run_on_start = true
}

resource "coder_app" "parsec_docs" {
  agent_id     = var.agent_id
  display_name = "Parsec Docs"
  slug         = "parsec-docs"
  icon         = var.icon
  url          = "https://support.parsec.app/hc/en-us"
  external     = true
  order        = var.order
  group        = var.group
}

output "parsec_status" {
  value       = "Parsec is configured. Connect using the Parsec app."
  description = "Status message for Parsec module"
}
