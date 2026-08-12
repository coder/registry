run "manual_mode" {
  command = plan

  variables {
    agent_id  = "test-agent-manual"
    vault_id  = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    api_token = "ocv_testtoken"
  }

  assert {
    condition     = length(coder_env.vault_id) == 1
    error_message = "ONECLAW_VAULT_ID should be set in manual mode"
  }

  assert {
    condition     = length(coder_env.agent_api_key) == 1
    error_message = "ONECLAW_AGENT_API_KEY should be set in manual mode"
  }

  assert {
    condition     = output.provisioning_mode == "manual"
    error_message = "provisioning_mode should be 'manual' when no human_api_key is set"
  }

  assert {
    condition     = output.module_directory == "$HOME/.coder-modules/kmjones1979/oneclaw"
    error_message = "module_directory should follow the standard module data layout"
  }

  assert {
    condition     = strcontains(local.install_script, "_ONECLAW_HUMAN_API_KEY")
    error_message = "Install script should read the human key from coder_env"
  }

  assert {
    condition     = length(module.coder_utils.scripts) == 1
    error_message = "coder-utils should expose the install script sync name"
  }
}

run "bootstrap_mode" {
  command = plan

  variables {
    agent_id      = "test-agent-bootstrap"
    human_api_key = "1ck_test_human_key"
  }

  assert {
    condition     = length(coder_env.vault_id) == 0
    error_message = "No vault_id env var in pure bootstrap mode (resolved inside workspace)"
  }

  assert {
    condition     = length(coder_env.agent_api_key) == 0
    error_message = "No agent_api_key env var in pure bootstrap mode (resolved inside workspace)"
  }

  assert {
    condition     = length(coder_env.human_api_key) == 1
    error_message = "Bootstrap mode should inject _ONECLAW_HUMAN_API_KEY via coder_env"
  }

  assert {
    condition     = coder_env.human_api_key[0].name == "_ONECLAW_HUMAN_API_KEY"
    error_message = "Human key env var should be named _ONECLAW_HUMAN_API_KEY"
  }

  assert {
    condition     = output.provisioning_mode == "bootstrap"
    error_message = "provisioning_mode should be 'bootstrap' when human_api_key is set"
  }

  assert {
    condition     = !strcontains(local.install_script, "1ck_test_human_key")
    error_message = "Human API key must not be templated into the install script body"
  }
}

run "manual_mode_no_human_key_env" {
  command = plan

  variables {
    agent_id  = "test-agent-manual-noenv"
    vault_id  = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    api_token = "ocv_testtoken"
  }

  assert {
    condition     = length(coder_env.human_api_key) == 0
    error_message = "Manual mode should not inject _ONECLAW_HUMAN_API_KEY"
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
    condition     = coder_env.base_url.value == "https://api.example.com"
    error_message = "ONECLAW_BASE_URL should match base_url"
  }
}
