terraform {
  required_version = ">= 1.0"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
    }
  }
}

variable "agent_id" {
  description = "The ID of a Coder agent."
  type        = string
}

variable "workdir" {
  description = "Directory the OpenCode server starts in. Created if missing. Clients can still pick another directory with `opencode attach --dir`."
  type        = string
  default     = "$HOME"
}

variable "port" {
  description = "Port for `opencode serve`."
  type        = number
  default     = 4096

  validation {
    condition     = var.port >= 1 && var.port <= 65535
    error_message = "port must be between 1 and 65535."
  }
}

variable "hostname" {
  description = "Address `opencode serve` listens on. Keep the default so the server is only reachable through Coder (port forwarding or the bundled app)."
  type        = string
  default     = "127.0.0.1"
}

variable "install_opencode" {
  description = "Whether to install OpenCode. Set to false when the image already ships OpenCode 1.x on PATH."
  type        = bool
  default     = true
}

variable "opencode_version" {
  description = "OpenCode 1.x release to install (e.g. `1.19.5`). Empty installs the latest 1.x release. Ignored when `install_opencode = false`."
  type        = string
  default     = ""

  validation {
    condition     = var.opencode_version == "" || can(regex("^v?1\\.[0-9]+\\.[0-9]+$", var.opencode_version))
    error_message = "opencode_version must be empty or an OpenCode 1.x release such as 1.19.5."
  }
}

variable "install_url" {
  description = "URL of the OpenCode 1.x installer script. Override to point at an internal mirror."
  type        = string
  default     = "https://opencode.ai/install"
}

variable "password_file" {
  description = "File holding the server's HTTP basic auth password (username `opencode`). Generated once if missing; persist it by keeping it on the home volume."
  type        = string
  default     = "$HOME/.config/opencode/server-password"
}

variable "enable_ai_gateway" {
  description = "Route OpenCode's Anthropic and OpenAI providers through this deployment's Coder AI Gateway, authenticated with the workspace owner's session token. Only applied when `config_json` is empty and no `opencode.json` exists yet."
  type        = bool
  default     = false
}

variable "config_json" {
  description = "Contents for the global `opencode.json`. When set, it overwrites the file on every start. When empty, an existing file is left alone."
  type        = string
  default     = ""
}

variable "web_app" {
  description = "Add a terminal app that runs `opencode attach` against the server."
  type        = bool
  default     = true
}

variable "app_display_name" {
  description = "Display name of the attach app."
  type        = string
  default     = "OpenCode"
}

variable "order" {
  description = "Position of the attach app in the Coder UI."
  type        = number
  default     = null
}

variable "group" {
  description = "Group for the attach app in the Coder UI."
  type        = string
  default     = null
}

variable "icon" {
  description = "Icon for the attach app and scripts."
  type        = string
  default     = "/icon/opencode.svg"
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

locals {
  module_directory = "$HOME/.coder-modules/droopy4096/opencode-server"
  ai_gateway_url   = "${trimsuffix(data.coder_workspace.me.access_url, "/")}/api/v2/ai-gateway"
  server_url       = "http://127.0.0.1:${var.port}"

  install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    ARG_INSTALL_OPENCODE  = tostring(var.install_opencode)
    ARG_OPENCODE_VERSION  = trimprefix(var.opencode_version, "v")
    ARG_INSTALL_URL       = var.install_url
    ARG_PASSWORD_FILE     = var.password_file
    ARG_ENABLE_AI_GATEWAY = tostring(var.enable_ai_gateway)
    ARG_CONFIG_JSON_B64   = base64encode(var.config_json)
  })

  start_script = templatefile("${path.module}/scripts/start.sh.tftpl", {
    ARG_WORKDIR       = var.workdir
    ARG_PORT          = tostring(var.port)
    ARG_HOSTNAME      = var.hostname
    ARG_PASSWORD_FILE = var.password_file
    ARG_LOG_FILE      = "${local.module_directory}/logs/server.log"
  })
}

# Session token and gateway URL reach the config through env placeholders, so
# they are never written into scripts or files.
resource "coder_env" "ai_gateway_url" {
  count    = var.enable_ai_gateway ? 1 : 0
  agent_id = var.agent_id
  name     = "OPENCODE_SERVER_AI_GATEWAY_URL"
  value    = local.ai_gateway_url
}

resource "coder_env" "ai_gateway_token" {
  count    = var.enable_ai_gateway ? 1 : 0
  agent_id = var.agent_id
  name     = "OPENCODE_SERVER_AI_GATEWAY_TOKEN"
  value    = data.coder_workspace_owner.me.session_token
}

module "coder_utils" {
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.1"

  agent_id            = var.agent_id
  module_directory    = local.module_directory
  display_name_prefix = "OpenCode server"
  icon                = var.icon
  install_script      = local.install_script
  start_script        = local.start_script
}

resource "coder_app" "attach" {
  count        = var.web_app ? 1 : 0
  agent_id     = var.agent_id
  slug         = "opencode-server"
  display_name = var.app_display_name
  icon         = var.icon
  order        = var.order
  group        = var.group
  open_in      = "slim-window"
  command      = <<-EOT
    #!/usr/bin/env bash
    export PATH="$HOME/.opencode/bin:$PATH"
    export OPENCODE_SERVER_PASSWORD="$(cat "${var.password_file}")"
    exec opencode attach ${local.server_url} --dir "${var.workdir}"
  EOT
}

output "port" {
  description = "Port the OpenCode server listens on."
  value       = var.port
}

output "server_url" {
  description = "Server URL inside the workspace."
  value       = local.server_url
}

output "password_file" {
  description = "Path of the file holding the server password."
  value       = var.password_file
}

output "scripts" {
  description = "Ordered `coder exp sync` names of the scripts this module creates, for serializing downstream scripts."
  value       = module.coder_utils.scripts
}
