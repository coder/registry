resource "coder_script" "install_claude_code" {
  agent_id     = var.agent_id
  display_name = "Install Claude Code"
  icon         = var.icon
  script       = file("${path.module}/scripts/install.sh")
  run_on_start = true

  env = {
    ARG_ENABLE_SUBAGENTS      = tostring(var.enable_subagents)
    ARG_SUBAGENTS_VERSION     = var.subagents_version
    ARG_CUSTOM_SUBAGENTS_PATH = var.custom_subagents_path
    ARG_ENABLED_SUBAGENTS     = jsonencode(var.enabled_subagents)
    ARG_DEFAULT_SUBAGENT_MODEL = var.default_subagent_model
  }
}
