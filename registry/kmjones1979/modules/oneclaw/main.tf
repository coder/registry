terraform {
  required_version = ">= 1.4"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.12"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

locals {
  # Which mode are we in?
  tf_native_mode = var.master_api_key != ""
  bootstrap_mode = var.human_api_key != "" && !local.tf_native_mode
  manual_mode    = !local.tf_native_mode && !local.bootstrap_mode

  provision_state_file = "${path.module}/.provision-state.json"

  provision_vault_name = (
    var.provision_vault_name != "" ? var.provision_vault_name :
    "coder-${data.coder_workspace.me.name}"
  )
  provision_agent_name = (
    var.provision_agent_name != "" ? var.provision_agent_name :
    "coder-${data.coder_workspace.me.name}-agent"
  )

  # Resolve effective vault_id and api_token.
  # In TF-native mode these come from the provision state file after null_resource runs.
  effective_vault_id = local.tf_native_mode ? local.provisioned_vault_id : var.vault_id
  effective_token    = local.tf_native_mode ? local.provisioned_token : var.api_token

  # Read provision state (only meaningful after null_resource.oneclaw_provision has run).
  provision_state = local.tf_native_mode && fileexists(local.provision_state_file) ? jsondecode(file(local.provision_state_file)) : {}

  provisioned_vault_id = lookup(local.provision_state, "vault_id", "")
  provisioned_token    = lookup(local.provision_state, "agent_api_key", "")
  provisioned_agent_id = lookup(local.provision_state, "agent_id", "")
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

# ===========================================================================
# Terraform-native provisioning (apply-time create, destroy-time cleanup)
# ===========================================================================

resource "null_resource" "oneclaw_provision" {
  count = local.tf_native_mode ? 1 : 0

  # All values needed at destroy time must live in triggers (Terraform restriction).
  triggers = {
    workspace_id   = data.coder_workspace.me.id
    workspace_name = data.coder_workspace.me.name
    vault_name     = local.provision_vault_name
    agent_name     = local.provision_agent_name
    state_file     = local.provision_state_file
    base_url       = var.base_url
    master_api_key = var.master_api_key
    destroy_vault  = tostring(var.auto_destroy_vault)
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command = templatefile("${path.module}/scripts/provision.sh", {
      BASE_URL          = var.base_url
      MASTER_API_KEY    = var.master_api_key
      WORKSPACE_ID      = data.coder_workspace.me.id
      WORKSPACE_NAME    = data.coder_workspace.me.name
      VAULT_NAME        = local.provision_vault_name
      AGENT_NAME        = local.provision_agent_name
      POLICY_PATH       = var.provision_policy_path
      TOKEN_TTL_SECONDS = tostring(var.token_ttl_hours * 3600)
      STATE_FILE        = local.provision_state_file
    })
  }

  provisioner "local-exec" {
    when        = destroy
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      STATE_FILE="${self.triggers.state_file}"
      API_URL="${self.triggers.base_url}"
      MASTER_KEY="${self.triggers.master_api_key}"
      DESTROY_VAULT="${self.triggers.destroy_vault}"

      if [ ! -f "$STATE_FILE" ]; then
        echo "[1claw-deprovision] No state file — nothing to clean up"
        exit 0
      fi

      VAULT_ID=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['vault_id'])")
      AGENT_ID=$(python3 -c "import json; print(json.load(open('$STATE_FILE'))['agent_id'])")
      echo "[1claw-deprovision] Agent: $AGENT_ID  Vault: $VAULT_ID"

      # Authenticate
      AUTH=$(curl -sf -w "\n%%{http_code}" \
        -H "Content-Type: application/json" \
        -d "{\"api_key\": \"$MASTER_KEY\"}" \
        "$API_URL/v1/auth/api-key-token" 2>&1) || {
        echo "[1claw-deprovision] WARN: Auth failed — manual cleanup needed"
        rm -f "$STATE_FILE"; exit 0
      }
      AUTH_HTTP=$(echo "$AUTH" | tail -1)
      AUTH_BODY=$(echo "$AUTH" | sed '$d')
      if [ "$(echo "$AUTH_HTTP" | head -c1)" != "2" ]; then
        echo "[1claw-deprovision] WARN: Auth HTTP $AUTH_HTTP — manual cleanup needed"
        rm -f "$STATE_FILE"; exit 0
      fi
      JWT=$(python3 -c "import json,sys; print(json.load(sys.stdin)['access_token'])" <<< "$AUTH_BODY")

      # Delete agent
      echo "[1claw-deprovision] Deleting agent $AGENT_ID..."
      curl -sf -X DELETE -H "Authorization: Bearer $JWT" "$API_URL/v1/agents/$AGENT_ID" >/dev/null 2>&1 \
        && echo "[1claw-deprovision] Agent deleted" \
        || echo "[1claw-deprovision] WARN: Agent delete failed (may already be gone)"

      # Optionally delete vault
      if [ "$DESTROY_VAULT" = "true" ]; then
        echo "[1claw-deprovision] Deleting vault $VAULT_ID..."
        curl -sf -X DELETE -H "Authorization: Bearer $JWT" "$API_URL/v1/vaults/$VAULT_ID" >/dev/null 2>&1 \
          && echo "[1claw-deprovision] Vault deleted" \
          || echo "[1claw-deprovision] WARN: Vault delete failed (may have secrets or already be gone)"
      else
        echo "[1claw-deprovision] Vault $VAULT_ID retained (set auto_destroy_vault = true to delete)"
      fi

      rm -f "$STATE_FILE"
      echo "[1claw-deprovision] Cleanup complete"
    EOT
  }
}

# ===========================================================================
# Environment variables (injected into the workspace agent)
# ===========================================================================

resource "coder_env" "oneclaw_vault_id" {
  count    = local.effective_vault_id != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "ONECLAW_VAULT_ID"
  value    = local.effective_vault_id
}

resource "coder_env" "oneclaw_agent_api_key" {
  count    = local.effective_token != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "ONECLAW_AGENT_API_KEY"
  value    = local.effective_token
}

resource "coder_env" "oneclaw_agent_id" {
  count    = var.agent_id_1claw != "" || local.provisioned_agent_id != "" ? 1 : 0
  agent_id = var.agent_id
  name     = "ONECLAW_AGENT_ID"
  value    = var.agent_id_1claw != "" ? var.agent_id_1claw : local.provisioned_agent_id
}

resource "coder_env" "oneclaw_base_url" {
  agent_id = var.agent_id
  name     = "ONECLAW_BASE_URL"
  value    = var.base_url
}

# ===========================================================================
# Shell bootstrap (optional, first-run provisioning inside the workspace)
# ===========================================================================

resource "coder_script" "oneclaw_bootstrap" {
  count              = local.bootstrap_mode ? 1 : 0
  agent_id           = var.agent_id
  display_name       = "1Claw Bootstrap"
  icon               = var.icon
  run_on_start       = true
  start_blocks_login = true

  script = templatefile("${path.module}/scripts/bootstrap.sh", {
    HUMAN_API_KEY = var.human_api_key
    BASE_URL      = var.base_url
    VAULT_ID      = var.vault_id
    VAULT_NAME    = var.bootstrap_vault_name
    AGENT_NAME    = var.bootstrap_agent_name != "" ? var.bootstrap_agent_name : "coder-${data.coder_workspace.me.name}"
    POLICY_PATH   = var.bootstrap_policy_path
    STATE_DIR     = "$HOME/.1claw"
  })
}

# ===========================================================================
# MCP config file injection
# ===========================================================================

resource "coder_script" "oneclaw_mcp_setup" {
  agent_id           = var.agent_id
  display_name       = "1Claw MCP Setup"
  icon               = var.icon
  run_on_start       = true
  start_blocks_login = false

  script = templatefile("${path.module}/scripts/setup.sh", {
    MCP_HOST              = var.mcp_host
    VAULT_ID              = local.effective_vault_id
    API_TOKEN             = local.effective_token
    BOOTSTRAP_MODE        = local.bootstrap_mode ? "true" : "false"
    INSTALL_CURSOR_CONFIG = var.install_cursor_config
    INSTALL_CLAUDE_CONFIG = var.install_claude_config
    CURSOR_CONFIG_PATH    = var.cursor_config_path
    CLAUDE_CONFIG_PATH    = var.claude_config_path
  })
}
