run "test_codex_basic" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder"
  }

  assert {
    condition     = var.workdir == "/home/coder"
    error_message = "Workdir should be set correctly"
  }

}

run "test_codex_with_api_key" {
  command = plan

  variables {
    agent_id       = "test-agent"
    workdir        = "/home/coder"
    openai_api_key = "test-key"
  }

  assert {
    condition     = coder_env.openai_api_key[0].value == "test-key"
    error_message = "OpenAI API key should be set correctly"
  }
}

run "test_codex_custom_options" {
  command = plan

  variables {
    agent_id      = "test-agent"
    workdir       = "/home/coder/project"
    icon          = "/icon/custom.svg"
    codex_version = "0.1.0"
  }

  assert {
    condition     = var.icon == "/icon/custom.svg"
    error_message = "Icon should be set to custom icon"
  }
}

run "test_ai_gateway_enabled" {
  command = plan

  variables {
    agent_id          = "test-agent"
    workdir           = "/home/coder"
    enable_ai_gateway = true
  }

  override_data {
    target = data.coder_workspace_owner.me
    values = {
      session_token = "mock-session-token"
    }
  }

  assert {
    condition     = var.enable_ai_gateway == true
    error_message = "AI Gateway should be enabled"
  }

  assert {
    condition     = coder_env.ai_gateway_session_token[0].name == "CODER_AIBRIDGE_SESSION_TOKEN"
    error_message = "CODER_AIBRIDGE_SESSION_TOKEN should be set"
  }

  assert {
    condition     = coder_env.ai_gateway_session_token[0].value == data.coder_workspace_owner.me.session_token
    error_message = "Session token should use workspace owner's token"
  }

  assert {
    condition     = length(coder_env.openai_api_key) == 0
    error_message = "OPENAI_API_KEY should not be created when ai_gateway is enabled"
  }
}

run "test_ai_gateway_validation_with_api_key" {
  command = plan

  variables {
    agent_id          = "test-agent"
    workdir           = "/home/coder"
    enable_ai_gateway = true
    openai_api_key    = "test-key"
  }

  expect_failures = [
    var.enable_ai_gateway,
  ]
}

run "test_ai_gateway_disabled_with_api_key" {
  command = plan

  variables {
    agent_id          = "test-agent"
    workdir           = "/home/coder"
    enable_ai_gateway = false
    openai_api_key    = "test-key-xyz"
  }

  assert {
    condition     = coder_env.openai_api_key[0].value == "test-key-xyz"
    error_message = "OPENAI_API_KEY should use the provided API key"
  }

  assert {
    condition     = length(coder_env.ai_gateway_session_token) == 0
    error_message = "Session token should not be set when ai_gateway is disabled"
  }
}

run "test_no_api_key_no_env" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder"
  }

  assert {
    condition     = length(coder_env.openai_api_key) == 0
    error_message = "OPENAI_API_KEY should not be created when no API key is provided"
  }
}

run "test_codex_with_scripts" {
  command = plan

  variables {
    agent_id            = "test-agent"
    workdir             = "/home/coder"
    pre_install_script  = "echo 'Pre-install script'"
    post_install_script = "echo 'Post-install script'"
  }

  assert {
    condition     = var.pre_install_script == "echo 'Pre-install script'"
    error_message = "Pre-install script should be set correctly"
  }

  assert {
    condition     = var.post_install_script == "echo 'Post-install script'"
    error_message = "Post-install script should be set correctly"
  }
}

run "test_script_outputs_install_only" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder"
  }

  assert {
    condition     = length(output.scripts) == 1 && output.scripts[0] == "coder-labs-codex-install_script"
    error_message = "scripts output should list only the install script when pre/post are not configured"
  }
}

run "test_script_outputs_with_pre_and_post" {
  command = plan

  variables {
    agent_id            = "test-agent"
    workdir             = "/home/coder"
    pre_install_script  = "echo pre"
    post_install_script = "echo post"
  }

  assert {
    condition     = output.scripts == ["coder-labs-codex-pre_install_script", "coder-labs-codex-install_script", "coder-labs-codex-post_install_script"]
    error_message = "scripts output should list pre_install, install, post_install in run order"
  }
}

run "test_workdir_optional" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = var.workdir == null
    error_message = "workdir should default to null when omitted"
  }
}
