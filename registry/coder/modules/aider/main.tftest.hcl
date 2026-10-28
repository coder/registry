run "defaults_are_correct" {
  command = plan

  variables {
    agent_id = "test-agent"
    model    = "gemini"
  }

  assert {
    condition     = var.install_aider == true
    error_message = "install_aider should default to true"
  }

  assert {
    condition     = local.workdir == ""
    error_message = "workdir should be empty by default"
  }

  assert {
    condition     = local.module_dir_name == ".coder-modules/coder/aider"
    error_message = "module_dir_name should be '.coder-modules/coder/aider'"
  }

  assert {
    condition     = coder_env.aider_model[0].name == "AIDER_MODEL" && coder_env.aider_model[0].value == "gemini"
    error_message = "AIDER_MODEL env var should be set from model"
  }

  assert {
    condition     = length(coder_env.api_key) == 0
    error_message = "No API key env var should be created when api_key is empty"
  }
}

run "workdir_trailing_slash_is_trimmed" {
  command = plan

  variables {
    agent_id = "test-agent"
    model    = "gemini"
    workdir  = "/home/coder/project/"
  }

  assert {
    condition     = local.workdir == "/home/coder/project"
    error_message = "workdir should have its trailing slash trimmed"
  }

  assert {
    condition     = strcontains(local.install_script, base64encode("/home/coder/project"))
    error_message = "install script should receive the base64-encoded workdir"
  }
}

run "api_key_uses_provider_env_var" {
  command = plan

  variables {
    agent_id    = "test-agent"
    model       = "sonnet"
    ai_provider = "anthropic"
    api_key     = "sk-ant-test-secret"
  }

  assert {
    condition     = coder_env.api_key[0].name == "ANTHROPIC_API_KEY" && coder_env.api_key[0].value == "sk-ant-test-secret"
    error_message = "ANTHROPIC_API_KEY env var should be created with the provided key"
  }

  assert {
    condition     = !strcontains(local.install_script, nonsensitive(var.api_key)) && !strcontains(local.install_script, base64encode(nonsensitive(var.api_key)))
    error_message = "API key should not be rendered into the install script"
  }
}

run "ollama_api_key_env_var" {
  command = plan

  variables {
    agent_id    = "test-agent"
    model       = "ollama_chat/llama3"
    ai_provider = "ollama"
    api_key     = "ollama-test-key"
  }

  assert {
    condition     = coder_env.api_key[0].name == "OLLAMA_API_KEY"
    error_message = "ollama should use OLLAMA_API_KEY"
  }
}

run "custom_provider_env_var" {
  command = plan

  variables {
    agent_id            = "test-agent"
    model               = "custom-model"
    ai_provider         = "custom"
    custom_env_var_name = "MY_CUSTOM_API_KEY"
    api_key             = "custom-test-key"
  }

  assert {
    condition     = coder_env.api_key[0].name == "MY_CUSTOM_API_KEY" && coder_env.api_key[0].value == "custom-test-key"
    error_message = "custom provider should use custom_env_var_name"
  }
}

run "custom_provider_without_env_var_name" {
  command = plan

  variables {
    agent_id    = "test-agent"
    model       = "custom-model"
    ai_provider = "custom"
    api_key     = "custom-test-key"
  }

  assert {
    condition     = length(coder_env.api_key) == 0
    error_message = "No API key env var should be created without custom_env_var_name"
  }
}

run "invalid_provider_is_rejected" {
  command = plan

  variables {
    agent_id    = "test-agent"
    model       = "gemini"
    ai_provider = "unknown"
  }

  expect_failures = [var.ai_provider]
}

run "base_aider_config_is_encoded" {
  command = plan

  variables {
    agent_id          = "test-agent"
    model             = "gemini"
    base_aider_config = "read:\n  - CONVENTIONS.md\ndark-mode: true\n"
  }

  assert {
    condition     = strcontains(local.install_script, base64encode("read:\n  - CONVENTIONS.md\ndark-mode: true"))
    error_message = "install script should receive the base64-encoded config without re-indentation"
  }
}

run "scripts_output_is_ordered" {
  command = plan

  variables {
    agent_id            = "test-agent"
    model               = "gemini"
    pre_install_script  = "echo pre"
    post_install_script = "echo post"
  }

  assert {
    condition     = output.scripts == ["coder-aider-pre_install_script", "coder-aider-install_script", "coder-aider-post_install_script"]
    error_message = "scripts output should be ordered pre_install, install, post_install"
  }
}

run "scripts_output_install_only" {
  command = plan

  variables {
    agent_id = "test-agent"
    model    = "gemini"
  }

  assert {
    condition     = output.scripts == ["coder-aider-install_script"]
    error_message = "scripts output should only contain install when no pre/post scripts are set"
  }
}
