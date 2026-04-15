run "manual_mode" {
  command = plan

  variables {
    agent_id  = "test-agent-manual"
    vault_id  = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    api_token = "ocv_testtoken"
  }

  assert {
    condition     = length(coder_env.oneclaw_vault_id) == 1
    error_message = "ONECLAW_VAULT_ID should be set in manual mode"
  }

  assert {
    condition     = length(coder_env.oneclaw_agent_api_key) == 1
    error_message = "ONECLAW_AGENT_API_KEY should be set in manual mode"
  }

  assert {
    condition     = length(null_resource.oneclaw_provision) == 0
    error_message = "No provision resource in manual mode"
  }

  assert {
    condition     = length(coder_script.oneclaw_bootstrap) == 0
    error_message = "No bootstrap script in manual mode"
  }
}

run "terraform_native_mode" {
  command = plan

  variables {
    agent_id       = "test-agent-tf"
    master_api_key = "1ck_test_master_key"
  }

  assert {
    condition     = length(null_resource.oneclaw_provision) == 1
    error_message = "Terraform-native mode should create the provision null_resource"
  }

  assert {
    condition     = length(coder_script.oneclaw_bootstrap) == 0
    error_message = "No bootstrap script in terraform-native mode"
  }
}

run "bootstrap_mode" {
  command = plan

  variables {
    agent_id      = "test-agent-bootstrap"
    human_api_key = "1ck_test_human_key"
  }

  assert {
    condition     = length(coder_script.oneclaw_bootstrap) == 1
    error_message = "Bootstrap mode should create the bootstrap script"
  }

  assert {
    condition     = length(null_resource.oneclaw_provision) == 0
    error_message = "No provision resource in bootstrap mode"
  }
}

run "master_key_takes_precedence_over_human" {
  command = plan

  variables {
    agent_id       = "test-agent-priority"
    master_api_key = "1ck_master"
    human_api_key  = "1ck_human"
  }

  assert {
    condition     = length(null_resource.oneclaw_provision) == 1
    error_message = "master_api_key should win when both keys are set"
  }

  assert {
    condition     = length(coder_script.oneclaw_bootstrap) == 0
    error_message = "No bootstrap script when master_api_key is set"
  }
}

run "custom_base_url" {
  command = plan

  variables {
    agent_id  = "test-agent-mcp"
    vault_id  = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    api_token = "ocv_testtoken"
    base_url  = "https://api.example.com"
  }

  assert {
    condition     = coder_env.oneclaw_base_url.value == "https://api.example.com"
    error_message = "ONECLAW_BASE_URL should match base_url"
  }
}
