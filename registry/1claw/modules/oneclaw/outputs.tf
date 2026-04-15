output "mcp_config_path" {
  description = "Primary MCP config file path (Cursor). Use this to reference the config from downstream resources."
  value       = var.cursor_config_path
}

output "claude_config_path" {
  description = "Claude Code MCP config file path."
  value       = var.install_claude_config ? var.claude_config_path : ""
}

output "vault_id" {
  description = "The 1Claw vault ID configured for this workspace."
  value       = nonsensitive(local.effective_vault_id)
}

output "scoped_token" {
  description = "The agent API key (ocv_) for this workspace. Only populated in Terraform-native mode."
  value       = local.provisioned_token
  sensitive   = true
}

output "agent_id_1claw" {
  description = "The 1Claw agent UUID provisioned for this workspace."
  value       = nonsensitive(local.provisioned_agent_id != "" ? local.provisioned_agent_id : var.agent_id_1claw)
}

output "provisioning_mode" {
  description = "Which provisioning mode is active: terraform_native, bootstrap, or manual."
  value = nonsensitive(
    local.tf_native_mode ? "terraform_native" : (local.bootstrap_mode ? "bootstrap" : "manual")
  )
}
