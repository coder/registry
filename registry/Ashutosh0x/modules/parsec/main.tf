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

variable "os" {
  type        = string
  description = "The operating system of the workspace (linux or windows)."
  default     = "linux"
  validation {
    condition     = contains(["linux", "windows"], var.os)
    error_message = "The os must be either 'linux' or 'windows'."
  }
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
  default     = "https://upload.wikimedia.org/wikipedia/commons/8/87/Parsec_icon.png"
}

variable "headless" {
  type        = bool
  description = "Run Parsec in headless mode (Linux only)."
  default     = true
}

resource "coder_script" "parsec_linux" {
  count        = var.os == "linux" ? 1 : 0
  agent_id     = var.agent_id
  display_name = "Parsec Installation (Linux)"
  icon         = var.icon

  script = <<-EOT
    #!/bin/bash
    set -e

    echo "=== Installing Parsec (Linux Client) ==="
    
    # Detect architecture
    ARCH=$(uname -m)
    if [ "$ARCH" != "x86_64" ]; then
      echo "Warning: Parsec only supports x86_64 architecture on Linux."
      echo "Skipping installation on $ARCH."
      exit 0
    fi

    # Check if Parsec is already installed
    if command -v parsecd &> /dev/null; then
      echo "Parsec is already installed"
    else
      echo "Downloading and installing Parsec..."
      
      PARSEC_URL="https://builds.parsec.app/package/parsec-linux.deb"
      
      # Download Parsec
      cd /tmp
      curl -fsSL -o parsec-linux.deb "$PARSEC_URL"
      
      # Install Parsec with non-interactive frontend
      export DEBIAN_FRONTEND=noninteractive
      
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
      # Note: Linux hosting is not officially supported by Parsec, but client mode works.
      cat > ~/.parsec/config.txt <<EOF
host_virtual_monitor = 1
host_privacy_mode = 1
app_daemon = 1
EOF
    fi

    echo "=== Parsec setup complete ==="
    echo "Note: Parsec on Linux is primarily a client. Hosting support is limited."
  EOT

  run_on_start = true
}

resource "coder_script" "parsec_windows" {
  count        = var.os == "windows" ? 1 : 0
  agent_id     = var.agent_id
  display_name = "Parsec Installation (Windows)"
  icon         = var.icon

  script = <<-EOT
    echo "=== Installing Parsec (Windows) ==="
    
    $InstallerPath = "$env:TEMP\parsec-windows.exe"
    $ParsecUrl = "https://builds.parsec.app/package/parsec-windows.exe"

    if (Test-Path "C:\Program Files\Parsec\parsecd.exe") {
        echo "Parsec is already installed."
    } else {
        echo "Downloading Parsec installer..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $ParsecUrl -OutFile $InstallerPath

        echo "Installing Parsec..."
        # /shared install allows access from login screen (service mode)
        # /silent suppresses UI
        Start-Process -FilePath $InstallerPath -ArgumentList "/shared", "/silent" -Wait -NoNewWindow

        echo "Parsec installed successfully."
    }

    echo "=== Parsec setup complete ==="
    echo "You can now connect to this workspace using Parsec."
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
}

output "parsec_status" {
  value       = "Parsec installed. For Windows, connect using the Parsec app. For Linux, Parsec is available as a client."
  description = "Status message for Parsec module"
}
