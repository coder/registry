variable "use_cli" {
  description = "Use the official VS Code CLI on glibc-based Linux or macOS (x64/arm64) to persist encrypted extension secrets in the browser. Requires an isolated application subdomain."
  type        = bool
  default     = false
}

moved {
  from = coder_script.vscode-web
  to   = coder_script.vscode-web[0]
}

locals {
  module_directory = "$HOME/.coder-modules/coder/vscode-web"
  cli_install_script = templatefile("${path.module}/scripts/install.sh.tftpl", {
    INSTALL_PREFIX_B64 = base64encode(var.install_prefix == "/tmp/vscode-web" ? "" : var.install_prefix)
    COMMIT_ID          = var.commit_id
    PLATFORM           = var.platform
    OFFLINE            = tostring(var.offline)
    USE_CACHED         = tostring(var.use_cached)
    LAUNCHER_B64       = filebase64("${path.module}/scripts/code-server.sh")
    PREPARE_SERVER_B64 = base64encode(templatefile("${path.module}/run.sh", {
      RUN_SERVER              = false
      PORT                    = var.port
      LOG_PATH                = ""
      INSTALL_PREFIX          = "$VSCODE_WEB_SERVER_DIR"
      COMMIT_ID               = "$VSCODE_WEB_COMMIT"
      PLATFORM                = "$VSCODE_WEB_PLATFORM"
      EXTENSIONS              = "$(printf '%s' '${base64encode(join(",", var.extensions))}' | base64 -d)"
      EXTENSIONS_DIR          = "$(printf '%s' '${base64encode(var.extensions_dir)}' | base64 -d)"
      TELEMETRY_LEVEL         = var.telemetry_level
      SETTINGS_B64            = base64encode(jsonencode(merge(var.settings, { "telemetry.telemetryLevel" = var.telemetry_level })))
      OFFLINE                 = var.offline
      USE_CACHED              = true
      DISABLE_TRUST           = false
      FOLDER                  = "$(printf '%s' '${base64encode(var.folder)}' | base64 -d)"
      WORKSPACE               = "$(printf '%s' '${base64encode(var.workspace)}' | base64 -d)"
      AUTO_INSTALL_EXTENSIONS = var.auto_install_extensions
      SERVER_BASE_PATH        = ""
    }))
  })
  cli_start_script = templatefile("${path.module}/scripts/start.sh.tftpl", {
    INSTALL_PREFIX_B64 = base64encode(var.install_prefix == "/tmp/vscode-web" ? "" : var.install_prefix)
    PORT               = var.port
    DISABLE_TRUST      = tostring(var.disable_trust)
    EXTENSIONS_DIR_B64 = base64encode(var.extensions_dir)
    TELEMETRY_LEVEL    = var.telemetry_level
    LOG_PATH_B64       = base64encode(var.log_path == "/tmp/vscode-web.log" ? "" : var.log_path)
  })
}

module "cli" {
  count   = var.use_cli ? 1 : 0
  source  = "registry.coder.com/coder/coder-utils/coder"
  version = "0.0.3"

  agent_id            = var.agent_id
  module_directory    = local.module_directory
  display_name_prefix = "VS Code Web"
  icon                = "/icon/code.svg"
  install_script      = local.cli_install_script
  start_script        = local.cli_start_script
}

output "scripts" {
  description = "Ordered script synchronization names for the CLI launch mode; empty for the legacy launch mode."
  value       = var.use_cli ? module.cli[0].scripts : []
}
