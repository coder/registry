run "defaults_are_correct" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = var.install_plandex == true
    error_message = "Plandex installation should be enabled by default"
  }

  assert {
    condition     = var.plandex_version == "latest"
    error_message = "Default Plandex version should be 'latest'"
  }

  assert {
    condition     = var.icon == "/icon/plandex.svg"
    error_message = "Default icon should be '/icon/plandex.svg'"
  }

  assert {
    condition     = var.workdir == null
    error_message = "Workdir should be null by default"
  }

  assert {
    condition     = var.openai_api_key == ""
    error_message = "OpenAI API key should default to empty"
  }

  assert {
    condition     = var.anthropic_api_key == ""
    error_message = "Anthropic API key should default to empty"
  }

  assert {
    condition     = var.google_api_key == ""
    error_message = "Google API key should default to empty"
  }

  assert {
    condition     = var.openrouter_api_key == ""
    error_message = "OpenRouter API key should default to empty"
  }

  assert {
    condition     = var.plandex_api_host == ""
    error_message = "Plandex API host should default to empty"
  }

  assert {
    condition     = local.module_dir_name == ".coder-modules/fran-mora/plandex"
    error_message = "Module dir name should follow the .coder-modules/<namespace>/<module> convention"
  }

  assert {
    condition     = local.workdir == ""
    error_message = "Workdir local should be empty string when var.workdir is null"
  }
}

run "workdir_trailing_slash_trimmed" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder/project/"
  }

  assert {
    condition     = local.workdir == "/home/coder/project"
    error_message = "Trailing slash on workdir should be trimmed"
  }
}

run "workdir_without_trailing_slash" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder/project"
  }

  assert {
    condition     = local.workdir == "/home/coder/project"
    error_message = "Workdir without trailing slash should pass through unchanged"
  }
}

run "plandex_version_pinning" {
  command = plan

  variables {
    agent_id        = "test-agent"
    plandex_version = "2.2.1"
  }

  assert {
    condition     = var.plandex_version == "2.2.1"
    error_message = "Plandex version should be settable"
  }
}

run "install_disabled" {
  command = plan

  variables {
    agent_id        = "test-agent"
    install_plandex = false
  }

  assert {
    condition     = var.install_plandex == false
    error_message = "Installation should be skippable"
  }
}

run "openai_api_key_creates_env_resource" {
  command = plan

  variables {
    agent_id       = "test-agent"
    openai_api_key = "sk-test-key"
  }

  assert {
    condition     = length(coder_env.openai_api_key) == 1
    error_message = "Setting openai_api_key should create exactly one coder_env resource"
  }

  assert {
    condition     = length(coder_env.anthropic_api_key) == 0
    error_message = "Anthropic env should not be created when only OpenAI key is set"
  }
}

run "multiple_provider_keys_create_multiple_env_resources" {
  command = plan

  variables {
    agent_id           = "test-agent"
    openai_api_key     = "sk-openai"
    anthropic_api_key  = "sk-ant"
    google_api_key     = "google-key"
    openrouter_api_key = "or-key"
  }

  assert {
    condition     = length(coder_env.openai_api_key) == 1
    error_message = "OpenAI env should be created when key is set"
  }

  assert {
    condition     = length(coder_env.anthropic_api_key) == 1
    error_message = "Anthropic env should be created when key is set"
  }

  assert {
    condition     = length(coder_env.google_api_key) == 1
    error_message = "Google env should be created when key is set"
  }

  assert {
    condition     = length(coder_env.openrouter_api_key) == 1
    error_message = "OpenRouter env should be created when key is set"
  }
}

run "no_api_keys_creates_no_env_resources" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = length(coder_env.openai_api_key) == 0
    error_message = "OpenAI env should not be created without a key"
  }

  assert {
    condition     = length(coder_env.anthropic_api_key) == 0
    error_message = "Anthropic env should not be created without a key"
  }

  assert {
    condition     = length(coder_env.google_api_key) == 0
    error_message = "Google env should not be created without a key"
  }

  assert {
    condition     = length(coder_env.openrouter_api_key) == 0
    error_message = "OpenRouter env should not be created without a key"
  }

  assert {
    condition     = length(coder_env.plandex_api_host) == 0
    error_message = "Plandex API host env should not be created without a value"
  }
}

run "self_hosted_api_host" {
  command = plan

  variables {
    agent_id         = "test-agent"
    plandex_api_host = "https://plandex.example.com"
  }

  assert {
    condition     = length(coder_env.plandex_api_host) == 1
    error_message = "Setting plandex_api_host should create the PLANDEX_API_HOST env resource"
  }

  assert {
    condition     = coder_env.plandex_api_host[0].value == "https://plandex.example.com"
    error_message = "PLANDEX_API_HOST should pass through the configured URL"
  }
}

run "custom_scripts_configuration" {
  command = plan

  variables {
    agent_id            = "test-agent"
    pre_install_script  = "#!/bin/bash\necho 'pre-install'"
    post_install_script = "#!/bin/bash\necho 'post-install'"
  }

  assert {
    condition     = var.pre_install_script != null
    error_message = "Pre-install script should be settable"
  }

  assert {
    condition     = var.post_install_script != null
    error_message = "Post-install script should be settable"
  }
}

run "custom_icon" {
  command = plan

  variables {
    agent_id = "test-agent"
    icon     = "/custom/icon.svg"
  }

  assert {
    condition     = var.icon == "/custom/icon.svg"
    error_message = "Custom icon should be settable"
  }
}
