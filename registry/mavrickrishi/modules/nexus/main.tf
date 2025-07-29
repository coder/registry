terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 0.23"
    }
  }
}

variable "nexus_url" {
  type        = string
  description = "Nexus repository URL. e.g. https://nexus.example.com"
  validation {
    condition     = can(regex("^(https|http)://", var.nexus_url))
    error_message = "nexus_url must be a valid URL starting with either 'https://' or 'http://'"
  }
}

variable "nexus_username" {
  type        = string
  description = "Username for Nexus authentication"
  default     = null
}

variable "nexus_password" {
  type        = string
  description = "Password or API token for Nexus authentication"
  sensitive   = true
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

variable "package_managers" {
  type = object({
    maven  = optional(list(string), [])
    npm    = optional(list(string), [])
    pypi   = optional(list(string), [])
    docker = optional(list(string), [])
  })
  default = {
    maven  = []
    npm    = []
    pypi   = []
    docker = []
  }
  description = <<-EOF
    A map of package manager names to their respective Nexus repositories. Unused package managers can be omitted.
    For example:
      {
        maven  = ["maven-public", "maven-releases"]
        npm    = ["npm-public", "@scoped:npm-private"]
        pypi   = ["pypi-public", "pypi-private"]
        docker = ["docker-public", "docker-private"]
      }
  EOF
}

variable "username_field" {
  type        = string
  description = "The field to use for the username. Default 'username'."
  default     = "username"
  validation {
    condition     = can(regex("^(email|username)$", var.username_field))
    error_message = "username_field must be either 'email' or 'username'"
  }
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

locals {
  username   = coalesce(var.nexus_username, var.username_field == "email" ? data.coder_workspace_owner.me.email : data.coder_workspace_owner.me.name)
  nexus_host = split("://", var.nexus_url)[1]
}

resource "coder_script" "nexus" {
  agent_id     = var.agent_id
  display_name = "nexus"
  icon         = "/icon/nexus.svg"
  script = <<-EOT
#!/usr/bin/env bash

not_configured() {
  type=$1
  echo "🤔 no $type repository is set, skipping $type configuration."
}

config_complete() {
  echo "🥳 Configuration complete!"
}

echo "🚀 Configuring Nexus repository access..."

# Configure Maven
if [ ${length(var.package_managers.maven)} -gt 0 ]; then
  echo "☕ Configuring Maven..."
  mkdir -p ~/.m2
  cat > ~/.m2/settings.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0">
  <servers>
    <server>
      <id>nexus</id>
      <username>${local.username}</username>
      <password>${var.nexus_password}</password>
    </server>
  </servers>
  <mirrors>
    <mirror>
      <id>nexus-mirror</id>
      <mirrorOf>*</mirrorOf>
      <url>${var.nexus_url}/repository/${try(element(var.package_managers.maven, 0), "maven-public")}</url>
    </mirror>
  </mirrors>
</settings>
EOF
  config_complete
else
  not_configured maven
fi

# Configure npm
if [ ${length(var.package_managers.npm)} -gt 0 ]; then
  echo "📦 Configuring npm..."
  cat > ~/.npmrc << 'EOF'
registry=${var.nexus_url}/repository/${try(element(var.package_managers.npm, 0), "npm-public")}/
//${local.nexus_host}/repository/${try(element(var.package_managers.npm, 0), "npm-public")}/:username=${local.username}
//${local.nexus_host}/repository/${try(element(var.package_managers.npm, 0), "npm-public")}/:_password=${base64encode(var.nexus_password)}
//${local.nexus_host}/repository/${try(element(var.package_managers.npm, 0), "npm-public")}/:always-auth=true
EOF
  config_complete
else
  not_configured npm
fi

# Configure pip
if [ ${length(var.package_managers.pypi)} -gt 0 ]; then
  echo "🐍 Configuring pip..."
  mkdir -p ~/.pip
  # Create .netrc file for secure credential storage
  cat > ~/.netrc << EOF
machine ${local.nexus_host}
login ${local.username}
password ${var.nexus_password}
EOF
  chmod 600 ~/.netrc

  # Update pip.conf to use index-url without embedded credentials
  cat > ~/.pip/pip.conf << 'EOF'
[global]
index-url = https://${local.nexus_host}/repository/${try(element(var.package_managers.pypi, 0), "pypi-public")}/simple
EOF
  config_complete
else
  not_configured pypi
fi

# Configure Docker
if [ ${length(var.package_managers.docker)} -gt 0 ]; then
  if command -v docker > /dev/null 2>&1; then
    echo "🐳 Configuring Docker credentials..."
    mkdir -p ~/.docker
    %{ for repo in var.package_managers.docker ~}
    echo -n "${var.nexus_password}" | docker login "${local.nexus_host}" --username "${local.username}" --password-stdin
    %{ endfor ~}
    config_complete
  else
    echo "🤔 Docker is not installed, skipping Docker configuration."
  fi
else
  not_configured docker
fi

echo "✅ Nexus repository configuration completed!"
EOT
  run_on_start = true
}

output "nexus_url" {
  description = "The Nexus repository URL"
  value       = var.nexus_url
}

output "username" {
  description = "The username used for Nexus authentication"
  value       = local.username
}