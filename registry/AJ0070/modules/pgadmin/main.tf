terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The agent to install pgAdmin on."
}

variable "port" {
  type        = number
  description = "The port to run pgAdmin on."
  default     = 5050
}

variable "subdomain" {
  type        = bool
  description = "If true, the app will be served on a subdomain."
  default     = true
}

variable "config" {
  type        = any
  description = "A map of pgAdmin configuration settings."
  default = {
    DEFAULT_EMAIL            = "admin@coder.com"
    DEFAULT_PASSWORD         = "coderPASSWORD"
    SERVER_MODE              = false
    MASTER_PASSWORD_REQUIRED = false
    LISTEN_ADDRESS           = "127.0.0.1"
  }
}

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

resource "coder_app" "pgadmin" {
  count        = data.coder_workspace.me.start_count
  agent_id     = var.agent_id
  display_name = "pgAdmin"
  slug         = "pgadmin"
  icon         = "/icon/pgadmin.svg"
  url          = local.url
  subdomain    = var.subdomain
  share        = "owner"

  healthcheck {
    url       = local.healthcheck_url
    interval  = 5
    threshold = 6
  }
}

resource "coder_script" "pgadmin" {
  agent_id     = var.agent_id
  display_name = "Install and run pgAdmin"
  icon         = "/icon/pgadmin.svg"
  run_on_start = true
  script = templatefile("${path.module}/run.sh", {
    PORT             = var.port,
    LOG_PATH         = "/tmp/pgadmin.log",
    SERVER_BASE_PATH = local.server_base_path,
    CONFIG           = local.config_content,
    PGADMIN_DATA_DIR = local.pgadmin_data_dir,
    PGADMIN_LOG_DIR  = local.pgadmin_log_dir,
    PGADMIN_VENV_DIR = local.pgadmin_venv_dir
  })
}

locals {
  server_base_path = var.subdomain ? "" : format("/@%s/%s/apps/%s", data.coder_workspace_owner.me.name, data.coder_workspace.me.name, "pgadmin")
  url              = "http://localhost:${var.port}${local.server_base_path}"
  healthcheck_url  = "http://localhost:${var.port}${local.server_base_path}/"

  # pgAdmin data directories (user-local paths)
  pgadmin_data_dir = "$HOME/.pgadmin"
  pgadmin_log_dir  = "$HOME/.pgadmin/logs"
  pgadmin_venv_dir = "$HOME/.pgadmin/venv"

  base_config = merge(var.config, {
    LISTEN_PORT = var.port
    # Override paths for user installation
    DATA_DIR        = local.pgadmin_data_dir
    LOG_FILE        = "${local.pgadmin_log_dir}/pgadmin4.log"
    SQLITE_PATH     = "${local.pgadmin_data_dir}/pgadmin4.db"
    SESSION_DB_PATH = "${local.pgadmin_data_dir}/sessions"
    STORAGE_DIR     = "${local.pgadmin_data_dir}/storage"
    # Disable initial setup prompts for automated deployment
    SETUP_AUTH = false
  })

  config_with_path = var.subdomain ? local.base_config : merge(local.base_config, {
    APPLICATION_ROOT = local.server_base_path
  })

  config_content = join("\n", [
    for key, value in local.config_with_path :
    format("%s = %s", key,
      can(regex("^(true|false)$", tostring(value))) ? (value ? "True" : "False") :
      can(tonumber(value)) ? tostring(value) :
      format("'%s'", tostring(value))
    )
  ])
}