run "manual_mode" {
  command = plan

  variables {
    agent_id  = "test-agent-manual"
    vault_id  = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    api_token = "ocv_testtoken"
  }

  assert {
    condition     = output.provisioning_mode == "manual"
    error_message = "Expected manual provisioning mode when only vault_id and api_token are set"
  }

  assert {
    condition     = length(coder_env.oneclaw_vault_id) == 1
    error_message = "ONECLAW_VAULT_ID should be set in manual mode"
  }

  assert {
    condition     = length(coder_env.oneclaw_agent_api_key) == 1
    error_message = "ONECLAW_AGENT_API_KEY should be set in manual mode"
  }
}

run "terraform_native_mode" {
  command = plan

  variables {
    agent_id       = "test-agent-tf"
    master_api_key = "1ck_test_master_key"
  }

  assert {
    condition     = output.provisioning_mode == "terraform_native"
    error_message = "Expected terraform_native when master_api_key is set"
  }

  assert {
    condition     = length(null_resource.oneclaw_provision) == 1
    error_message = "Terraform-native mode should create the provision null_resource"
  }
}

run "bootstrap_mode" {
  command = plan

  variables {
    agent_id        = "test-agent-bootstrap"
    human_api_key   = "1ck_test_human_key"
    bootstrap_vault_name = "test-vault"
  }

  assert {
    condition     = output.provisioning_mode == "bootstrap"
    error_message = "Expected bootstrap mode when human_api_key is set without master_api_key"
  }

  assert {
    condition     = length(coder_script.oneclaw_bootstrap) == 1
    error_message = "Bootstrap mode should create the bootstrap script"
  }
}

run "master_key_takes_precedence_over_human" {
  command = plan

  variables {
    agent_id        = "test-agent-priority"
    master_api_key  = "1ck_master"
    human_api_key   = "1ck_human"
  }

  assert {
    condition     = output.provisioning_mode == "terraform_native"
    error_message = "master_api_key should win when both keys are set"
  }
}

run "mcp_endpoints" {
  command = plan

  variables {
    agent_id  = "test-agent-mcp"
    vault_id  = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    api_token = "ocv_testtoken"
    mcp_host  = "https://mcp.example.com/mcp"
    base_url  = "https://api.example.com"
  }

  assert {
    condition     = coder_env.oneclaw_base_url.value == "https://api.example.com"
    error_message = "ONECLAW_BASE_URL should match base_url"
  }
}
