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
    }
  }

  assert {
    condition     = coder_env.extra_env["MISTRAL_API_KEY"].name == "MISTRAL_API_KEY"
    error_message = "extra_env should create a coder_env resource named after the map key"
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
