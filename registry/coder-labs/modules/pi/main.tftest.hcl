run "test_pi_basic" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder"
  }

  assert {
    condition     = var.install_pi == true
    error_message = "install_pi should default to true"
  }

  assert {
    condition     = var.default_project_trust == "always"
    error_message = "default_project_trust should default to always"
  }
}

run "test_pi_with_api_key" {
  command = plan

  variables {
    agent_id          = "test-agent"
    workdir           = "/home/coder"
    anthropic_api_key = "test-key"
  }

  assert {
    condition     = coder_env.anthropic_api_key[0].value == "test-key"
    error_message = "Anthropic API key should be set correctly"
  }

  assert {
    condition     = !strcontains(local.install_script, nonsensitive(var.anthropic_api_key))
    error_message = "Anthropic API key should not be rendered into the install script"
  }
}

run "test_no_api_key_no_env" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder"
  }

  assert {
    condition     = length(coder_env.anthropic_api_key) == 0
    error_message = "ANTHROPIC_API_KEY should not be created when no API key is provided"
  }

  assert {
    condition     = length(coder_env.openai_api_key) == 0
    error_message = "OPENAI_API_KEY should not be created when no API key is provided"
  }

  assert {
    condition     = length(coder_env.gemini_api_key) == 0
    error_message = "GEMINI_API_KEY should not be created when no API key is provided"
  }
}

run "test_extra_env" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder"
    extra_env = {
      MISTRAL_API_KEY = "test-mistral-key"
      PI_OFFLINE      = "1"
    }
  }

  assert {
    condition     = coder_env.extra_env["MISTRAL_API_KEY"].name == "MISTRAL_API_KEY"
    error_message = "extra_env should create a coder_env resource named after the map key"
  }

  assert {
    condition     = length(coder_env.extra_env) == 2 && coder_env.extra_env["PI_OFFLINE"].value == "1"
    error_message = "extra_env should create one coder_env resource per map entry"
  }

  assert {
    condition     = !strcontains(local.install_script, "test-mistral-key")
    error_message = "extra_env values should not be rendered into the install script"
  }
}

run "test_default_project_trust_validation" {
  command = plan

  variables {
    agent_id              = "test-agent"
    default_project_trust = "invalid"
  }

  expect_failures = [
    var.default_project_trust,
  ]
}

run "test_pi_custom_options" {
  command = plan

  variables {
    agent_id   = "test-agent"
    workdir    = "/home/coder/project"
    icon       = "/icon/custom.svg"
    pi_version = "0.12.0"
  }

  assert {
    condition     = length(output.scripts) > 0
    error_message = "scripts output should be non-empty with custom options"
  }
}

run "test_workdir_optional" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = length(output.scripts) == 1
    error_message = "scripts output should have install script even without workdir"
  }
}

run "test_script_outputs_install_only" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder"
  }

  assert {
    condition     = length(output.scripts) == 1 && output.scripts[0] == "coder-labs-pi-install_script"
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
    condition     = output.scripts == ["coder-labs-pi-pre_install_script", "coder-labs-pi-install_script", "coder-labs-pi-post_install_script"]
    error_message = "scripts output should list pre_install, install, post_install in run order"
  }
}

run "test_ai_gateway_enabled" {
  command = plan

  variables {
    agent_id          = "test-agent"
    enable_ai_gateway = true
  }

  override_data {
    target = data.coder_workspace.me
    values = {
      access_url = "https://coder.example.com/"
    }
  }

  override_data {
    target = data.coder_workspace_owner.me
    values = {
      session_token = "mock-session-token"
    }
  }

  assert {
    condition     = coder_env.ai_gateway_anthropic_token[0].name == "ANTHROPIC_API_KEY" && coder_env.ai_gateway_anthropic_token[0].value == "mock-session-token"
    error_message = "AI Gateway should authenticate the Anthropic provider with the workspace owner's session token"
  }

  assert {
    condition     = coder_env.ai_gateway_openai_token[0].name == "OPENAI_API_KEY" && coder_env.ai_gateway_openai_token[0].value == "mock-session-token"
    error_message = "AI Gateway should authenticate the OpenAI provider with the workspace owner's session token"
  }

  assert {
    condition     = length(coder_env.anthropic_api_key) == 0 && length(coder_env.openai_api_key) == 0
    error_message = "Direct provider keys should not be set when AI Gateway is enabled"
  }

  assert {
    condition     = local.ai_gateway_base_url == "https://coder.example.com/api/v2/ai-gateway"
    error_message = "AI Gateway base URL should be derived from the access URL without a double slash"
  }

  assert {
    condition     = strcontains(local.install_script, "ARG_AI_GATEWAY_BASE_URL='https://coder.example.com/api/v2/ai-gateway'")
    error_message = "Install script should receive the AI Gateway base URL"
  }

  assert {
    condition     = !strcontains(local.install_script, "mock-session-token")
    error_message = "Session token should not be rendered into the install script"
  }
}

run "test_ai_gateway_disabled_by_default" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = length(coder_env.ai_gateway_anthropic_token) == 0 && length(coder_env.ai_gateway_openai_token) == 0
    error_message = "AI Gateway env vars should not be created by default"
  }

  assert {
    condition     = strcontains(local.install_script, "ARG_AI_GATEWAY_BASE_URL=''")
    error_message = "Install script should not configure AI Gateway by default"
  }
}

run "test_ai_gateway_rejects_anthropic_api_key" {
  command = plan

  variables {
    agent_id          = "test-agent"
    enable_ai_gateway = true
    anthropic_api_key = "test-key"
  }

  expect_failures = [var.anthropic_api_key]
}

run "test_ai_gateway_rejects_openai_api_key" {
  command = plan

  variables {
    agent_id          = "test-agent"
    enable_ai_gateway = true
    openai_api_key    = "test-key"
  }

  expect_failures = [var.openai_api_key]
}

run "test_npm_registry_url" {
  command = plan

  variables {
    agent_id         = "test-agent"
    npm_registry_url = "https://npm.internal.example.com/"
  }

  assert {
    condition     = strcontains(local.install_script, "ARG_NPM_REGISTRY_URL='https://npm.internal.example.com/'")
    error_message = "Install script should receive the npm registry URL"
  }
}

run "test_npm_registry_url_validation" {
  command = plan

  variables {
    agent_id         = "test-agent"
    npm_registry_url = "npm.internal.example.com"
  }

  expect_failures = [var.npm_registry_url]
}

run "test_pi_binary_path" {
  command = plan

  variables {
    agent_id       = "test-agent"
    install_pi     = false
    pi_binary_path = "/opt/pi/bin/pi"
  }

  assert {
    condition     = strcontains(local.install_script, base64encode("/opt/pi/bin/pi"))
    error_message = "Install script should receive the encoded Pi binary path"
  }
}

run "test_pi_binary_path_must_be_absolute" {
  command = plan

  variables {
    agent_id       = "test-agent"
    install_pi     = false
    pi_binary_path = "bin/pi"
  }

  expect_failures = [var.pi_binary_path]
}

run "test_pi_binary_path_requires_install_disabled" {
  command = plan

  variables {
    agent_id       = "test-agent"
    pi_binary_path = "/opt/pi/bin/pi"
  }

  expect_failures = [var.pi_binary_path]
}
