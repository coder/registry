run "defaults_are_correct" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder"
  }

  assert {
    condition     = var.copilot_model == "claude-sonnet-4.5"
    error_message = "Default model should be 'claude-sonnet-4.5'"
  }

  assert {
    condition     = var.install_copilot == true
    error_message = "install_copilot should default to true"
  }

  assert {
    condition     = local.module_dir_name == ".coder-modules/coder-labs/copilot"
    error_message = "module_dir_name should be '.coder-modules/coder-labs/copilot'"
  }
}

run "github_token_creates_env_vars" {
  command = plan

  variables {
    agent_id     = "test-agent"
    workdir      = "/home/coder"
    github_token = "test_github_token_abc123"
  }

  assert {
    condition     = coder_env.github_token[0].name == "COPILOT_GITHUB_TOKEN" && coder_env.github_token[0].value == "test_github_token_abc123"
    error_message = "COPILOT_GITHUB_TOKEN env var should be created with the provided token"
  }
}

run "github_token_not_created_when_empty" {
  command = plan

  variables {
    agent_id     = "test-agent"
    workdir      = "/home/coder"
    github_token = ""
  }

  assert {
    condition     = length(coder_env.github_token) == 0
    error_message = "GitHub token env var should not be created when empty"
  }
}

run "copilot_model_env_var_uses_given_model" {
  command = plan

  variables {
    agent_id      = "test-agent"
    workdir       = "/home/coder"
    copilot_model = "claude-sonnet-4"
  }

  assert {
    condition     = coder_env.copilot_model[0].name == "COPILOT_MODEL" && coder_env.copilot_model[0].value == "claude-sonnet-4"
    error_message = "COPILOT_MODEL env var should be created with the given model"
  }
}

run "copilot_model_env_var_is_always_set" {
  command = plan

  variables {
    agent_id      = "test-agent"
    workdir       = "/home/coder"
    copilot_model = "claude-sonnet-4.5"
  }

  assert {
    condition     = coder_env.copilot_model[0].name == "COPILOT_MODEL" && coder_env.copilot_model[0].value == "claude-sonnet-4.5"
    error_message = "COPILOT_MODEL env var should be set to the model as given, including the default"
  }
}

run "workdir_trimmed_and_trusted" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder/project/"
  }

  assert {
    condition     = local.workdir == "/home/coder/project"
    error_message = "workdir should be trimmed of trailing slash"
  }

  assert {
    condition     = contains(local.workdir_trusted_folders, "/home/coder/project")
    error_message = "workdir should be trusted automatically"
  }
}

run "workdir_optional" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = local.workdir == ""
    error_message = "workdir should default to an empty string"
  }

  assert {
    condition     = length(output.scripts) == 1
    error_message = "scripts output should have the install script even without a workdir"
  }
}

run "script_outputs_install_only" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder"
  }

  assert {
    condition     = output.scripts == ["coder-labs-copilot-install_script"]
    error_message = "scripts output should list only the install script when pre/post are not configured"
  }
}

run "script_outputs_with_pre_and_post" {
  command = plan

  variables {
    agent_id            = "test-agent"
    workdir             = "/home/coder"
    pre_install_script  = "echo pre"
    post_install_script = "echo post"
  }

  assert {
    condition     = output.scripts == ["coder-labs-copilot-pre_install_script", "coder-labs-copilot-install_script", "coder-labs-copilot-post_install_script"]
    error_message = "scripts output should list pre_install, install, post_install in run order"
  }
}

run "ai_gateway_disabled_creates_no_proxy_env" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder"
  }

  assert {
    condition     = length(coder_env.ai_gateway_https_proxy) == 0 && length(coder_env.ai_gateway_node_extra_ca_certs) == 0
    error_message = "No proxy env vars should be created when enable_ai_gateway is false"
  }
}

run "ai_gateway_enabled_sets_proxy_env" {
  command = plan

  variables {
    agent_id             = "test-agent"
    workdir              = "/home/coder"
    enable_ai_gateway    = true
    ai_gateway_auth_url  = "https://coder:mock-token@aiproxy.example.com"
    ai_gateway_cert_path = "/tmp/aibridge-proxy/ca-cert.pem"
  }

  assert {
    condition     = coder_env.ai_gateway_https_proxy[0].name == "HTTPS_PROXY" && coder_env.ai_gateway_https_proxy[0].value == "https://coder:mock-token@aiproxy.example.com"
    error_message = "HTTPS_PROXY should be set to ai_gateway_auth_url"
  }

  assert {
    condition     = coder_env.ai_gateway_node_extra_ca_certs[0].name == "NODE_EXTRA_CA_CERTS" && coder_env.ai_gateway_node_extra_ca_certs[0].value == "/tmp/aibridge-proxy/ca-cert.pem"
    error_message = "NODE_EXTRA_CA_CERTS should be set to ai_gateway_cert_path"
  }
}

run "ai_gateway_requires_auth_url" {
  command = plan

  variables {
    agent_id             = "test-agent"
    workdir              = "/home/coder"
    enable_ai_gateway    = true
    ai_gateway_cert_path = "/tmp/aibridge-proxy/ca-cert.pem"
  }

  expect_failures = [
    var.enable_ai_gateway,
  ]
}

run "ai_gateway_requires_cert_path" {
  command = plan

  variables {
    agent_id            = "test-agent"
    workdir             = "/home/coder"
    enable_ai_gateway   = true
    ai_gateway_auth_url = "https://coder:mock-token@aiproxy.example.com"
  }

  expect_failures = [
    var.enable_ai_gateway,
  ]
}
