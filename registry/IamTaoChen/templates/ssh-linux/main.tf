terraform {
  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6"
    }
  }
}

provider "coder" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}


data "coder_parameter" "host" {
  description  = "Remote Host or IP"
  display_name = "Host"
  name         = "host"
  type         = "string"
  default      = "192.168.1.1"
  mutable      = false
  order        = 1
  validation {
    regex = "^[a-zA-Z0-9:.%\\-]+$"
    error = "Please enter a valid hostname, IPv4, or IPv6 address. Examples: example.com, 192.168.1.1, or fe80::1"
  }
}

data "coder_parameter" "username" {
  default      = data.coder_workspace_owner.me.name
  description  = "SSH Username"
  display_name = "Username"
  name         = "username"
  mutable      = false
  order        = 2
}

data "coder_parameter" "auth_type" {
  name         = "auth_type"
  display_name = "SSH Auth Type"
  description  = "Authentication method for SSH"
  type         = "string"

  form_type = "dropdown"
  default   = "password"
  mutable   = true
  order     = 3
  option {
    name  = "password"
    value = "password"
  }

  option {
    name  = "SSH Key Manual"
    value = "ssh_key"
  }

  option {
    name  = "SSH Key from Coder"
    value = "ssh_key_coder"
  }

}

data "coder_parameter" "ssh_password" {
  count        = data.coder_parameter.auth_type.value == "password" ? 1 : 0
  name         = "ssh_password"
  display_name = "SSH Password"
  description  = "Password for SSH login"
  type         = "string"
  mutable      = true
  styling = jsonencode({
    mask_input = true
  })
  order = 4
}

data "coder_parameter" "ssh_key" {
  count        = data.coder_parameter.auth_type.value == "ssh_key" ? 1 : 0
  name         = "ssh_key"
  display_name = "SSH Private Key"
  description  = "Paste SSH private key"
  type         = "string"
  mutable      = true
  form_type    = "textarea"
  styling = jsonencode({
    mask_input = true
  })
  order = 4
}

data "coder_parameter" "ssh_key_coder" {
  count        = data.coder_parameter.auth_type.value == "ssh_key_coder" ? 1 : 0
  name         = "ssh_key_coder"
  display_name = "Public Key From Coder"
  description  = "Add this public key to your remote server's authorized_keys: \n\n${data.coder_workspace_owner.me.ssh_public_key}"
  default = "********************"
  styling = jsonencode({
    disabled = true
    mask_input = true
  })
  order = 4
}


data "coder_parameter" "port" {
  default      = 22
  description  = "SSH Port"
  display_name = "Port"
  name         = "port"
  type         = "number"
  mutable      = true
  order        = 5
  validation {
    min   = 1
    max   = 65535
    error = "Port must be between 1 and 65535"
  }
}

data "coder_parameter" "apps" {
  name         = "apps"
  display_name = "Choose any APPs for your workspace."
  type         = "list(string)"
  form_type    = "multi-select"
  mutable      = true
  default      = jsonencode(["VS Code Desktop"])
  dynamic "option" {
    for_each = local.apps_candidate
    content {
      name  = option.value
      value = option.value
    }
  }
}

locals {
  username        = data.coder_parameter.username.value
  home_dir        = "/home/${lower(local.username)}"
  coder_cache_dir = "${local.home_dir}/.coder/${data.coder_workspace.me.id}"
  agent_id_file   = "${local.coder_cache_dir}/agent.id"
  use_password    = data.coder_parameter.auth_type.value == "password"
  use_key         = contains(["ssh_key", "ssh_key_coder"],data.coder_parameter.auth_type.value)
  ssh_password    = local.use_password ? data.coder_parameter.ssh_password[0].value : null
  ssh_private_key = data.coder_parameter.auth_type.value == "ssh_key_coder" ? data.coder_workspace_owner.me.ssh_private_key : (length(data.coder_parameter.ssh_key) > 0 ? data.coder_parameter.ssh_key[0].value : null )
  apps_candidate  = ["VS Code Desktop", "VS Code Web", "Cursor"]
  apps_selected   = (can(data.coder_parameter.apps.value) && data.coder_parameter.apps.value != "") ? jsondecode(data.coder_parameter.apps.value) : []
}

resource "random_integer" "vs_code_port" {
  min = 54000
  max = 55999
}

resource "coder_agent" "main" {
  os   = "linux"
  arch = "amd64"

  startup_script = <<-EOT
    #!/bin/bash
    set -euo pipefail
  EOT

  env = {
    GIT_AUTHOR_NAME     = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace_owner.me.email}"
    GIT_COMMITTER_NAME  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
    GIT_COMMITTER_EMAIL = "${data.coder_workspace_owner.me.email}"
  }

  display_apps {
    port_forwarding_helper = true
    vscode                 = contains(local.apps_selected, "VS Code Desktop")
    vscode_insiders        = false
    web_terminal           = true
    ssh_helper             = true
  }

  metadata {
    key          = "cpu"
    display_name = "CPU Usage"
    interval     = 5
    timeout      = 5
    script       = "coder stat cpu"
  }
  metadata {
    key          = "memory"
    display_name = "Memory Usage"
    interval     = 5
    timeout      = 5
    script       = "coder stat mem"
  }
  metadata {
    key          = "disk"
    display_name = "Home Disk Usage"
    interval     = 600
    timeout      = 30
    script       = "coder stat disk --path ${lower(local.home_dir)}"
  }
}

resource "null_resource" "deploy_coder_agent" {
  count = data.coder_workspace.me.start_count

  triggers = {
    init_script = sha256(coder_agent.main.init_script)
    token       = coder_agent.main.token
  }

  connection {
    type        = "ssh"
    host        = data.coder_parameter.host.value
    user        = data.coder_parameter.username.value
    port        = data.coder_parameter.port.value
    password    = local.ssh_password
    private_key = local.ssh_private_key
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "mkdir -p ${local.coder_cache_dir}",
      "coder_sh=${local.coder_cache_dir}/coder.sh",
      "log_file=${local.coder_cache_dir}/coder.log",
      "cat > $coder_sh << 'EOF'",
      "${coder_agent.main.init_script}",
      "EOF",
      "chmod +x $coder_sh",
      "echo \"$(date) : create $coder_sh\" >> ${local.coder_cache_dir}/debug.log",
      "nohup env CODER_AGENT_TOKEN='${coder_agent.main.token}' $coder_sh > $log_file 2>&1 &",
      "echo $! > ${local.agent_id_file}",
      "echo \"$(date) : run $coder_sh and log at $log_file\" >> ${local.coder_cache_dir}/debug.log",
    ]
  }
}

resource "null_resource" "coder_stop" {
  count = (try(data.coder_workspace.me.start_count, 1) > 0 ? 0 : 1)

  connection {
    type        = "ssh"
    host        = data.coder_parameter.host.value
    user        = data.coder_parameter.username.value
    port        = data.coder_parameter.port.value
    password    = local.ssh_password
    private_key = local.ssh_private_key
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      "set -u",
      "PID_FILE=${local.agent_id_file}",
      # Only proceed if PID file exists
      "if [ -f \"$PID_FILE\" ]; then",
      "  PID=$(cat \"$PID_FILE\")",
      #   Check if it's actually a number and process exists
      "  if [ -n \"$PID\" ] && echo \"$PID\" | grep -q '^[0-9][0-9]*$' && kill -0 \"$PID\" 2>/dev/null; then",
      "    echo \"Gracefully stopping process $PID...\"",
      #    First try graceful termination
      "    kill -TERM \"$PID\" 2>/dev/null || true",
      #     Wait and check repeatedly (up to ~15 seconds total)
      "    for i in $(seq 1 15); do",
      "      sleep 1",
      "      if ! kill -0 \"$PID\" 2>/dev/null; then",
      "        echo \"Process $PID terminated gracefully\"",
      "        break",
      "      fi",
      #      Show we're still waiting (every 5 seconds)
      "      expr $i % 5 = 0 >/dev/null && echo \"Still waiting... ($i/15 seconds)\"",
      "    done",
      #     Final check - only kill -9 if still alive"
      "    if kill -0 \"$PID\" 2>/dev/null; then",
      "      echo \"Process $PID did not terminate in time - sending SIGKILL\"",
      "      kill -KILL \"$PID\" 2>/dev/null || true",
      "    fi",
      "  else",
      "    echo \"No running process found for PID $PID (or invalid PID)\"",
      "  fi",
      "  ",
      #  Clean lean up regardless of whether kill succeeded
      "  rm -f \"$PID_FILE\"",
      "  rm -rf ${local.coder_cache_dir} 2>/dev/null || true",
      "else",
      "  echo \"PID file not found: $PID_FILE - nothing to clean up\"",
      "fi",
      "sync 2>/dev/null || true",
    ]
  }
}


module "coder-login" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.1.1"
  agent_id = coder_agent.main.id
}

module "cursor" {
  count    = contains(local.apps_selected, "Cursor") ? data.coder_workspace.me.start_count : 0
  source   = "registry.coder.com/coder/cursor/coder"
  version  = "1.4.0"
  agent_id = coder_agent.main.id
}

module "vscode-web" {
  count          = contains(local.apps_selected, "VS Code Web") ? data.coder_workspace.me.start_count : 0
  source         = "registry.coder.com/coder/vscode-web/coder"
  version        = "1.4.3"
  agent_id       = coder_agent.main.id
  folder         = local.home_dir
  port           = random_integer.vs_code_port.result
  accept_license = true
}
