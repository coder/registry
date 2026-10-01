run "defaults_are_correct" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = var.install_kiro_cli == true
    error_message = "install_kiro_cli should default to true"
  }

  assert {
    condition     = var.kiro_cli_version == "latest"
    error_message = "kiro_cli_version should default to latest"
  }

  assert {
    condition     = local.workdir == ""
    error_message = "workdir should be empty by default"
  }

  assert {
    condition     = local.module_dir_name == ".coder-modules/harleylrn/kiro-cli"
    error_message = "module_dir_name should be '.coder-modules/harleylrn/kiro-cli'"
  }

  assert {
    condition     = length(coder_env.auth_tarball) == 0 && length(coder_env.kiro_api_key) == 0
    error_message = "No auth env vars should be created by default"
  }
}

run "workdir_trailing_slash_is_trimmed" {
  command = plan

  variables {
    agent_id = "test-agent"
    workdir  = "/home/coder/project/"
  }

  assert {
    condition     = local.workdir == "/home/coder/project"
    error_message = "workdir should have its trailing slash trimmed"
  }
}

run "api_key_creates_env_var" {
  command = plan

  variables {
    agent_id = "test-agent"
    api_key  = "ksk_test-kiro-key"
  }

  assert {
    condition     = coder_env.kiro_api_key[0].name == "KIRO_API_KEY" && coder_env.kiro_api_key[0].value == "ksk_test-kiro-key"
    error_message = "KIRO_API_KEY env var should be created with the provided key"
  }

  assert {
    condition     = !strcontains(local.install_script, nonsensitive(var.api_key)) && !strcontains(local.install_script, base64encode(nonsensitive(var.api_key)))
    error_message = "API key should not be rendered into the install script"
  }
}

run "auth_tarball_creates_env_var" {
  command = plan

  variables {
    agent_id     = "test-agent"
    auth_tarball = "dGVzdEF1dGhUYXJiYWxs"
  }

  assert {
    condition     = coder_env.auth_tarball[0].name == "KIRO_CLI_AUTH_TARBALL" && coder_env.auth_tarball[0].value == "dGVzdEF1dGhUYXJiYWxs"
    error_message = "KIRO_CLI_AUTH_TARBALL env var should be created with the provided tarball"
  }

  assert {
    condition     = !strcontains(local.install_script, nonsensitive(var.auth_tarball))
    error_message = "Auth tarball should not be rendered into the install script"
  }
}

run "invalid_version_fails" {
  command = plan

  variables {
    agent_id         = "test-agent"
    kiro_cli_version = "2.26.0'; rm -rf /"
  }

  expect_failures = [
    var.kiro_cli_version,
  ]
}

run "invalid_mcp_fails" {
  command = plan

  variables {
    agent_id = "test-agent"
    mcp      = "{\"servers\": {}}"
  }

  expect_failures = [
    var.mcp,
  ]
}

run "agent_config_requires_plain_name" {
  command = plan

  variables {
    agent_id     = "test-agent"
    agent_config = "{\"name\": \"../escape\"}"
  }

  expect_failures = [
    var.agent_config,
  ]
}

run "agent_config_requires_name" {
  command = plan

  variables {
    agent_id     = "test-agent"
    agent_config = "{\"description\": \"no name\"}"
  }

  expect_failures = [
    var.agent_config,
  ]
}

run "scripts_output_is_ordered" {
  command = plan

  variables {
    agent_id            = "test-agent"
    pre_install_script  = "echo pre"
    post_install_script = "echo post"
  }

  assert {
    condition     = output.scripts == ["harleylrn-kiro-cli-pre_install_script", "harleylrn-kiro-cli-install_script", "harleylrn-kiro-cli-post_install_script"]
    error_message = "scripts output should be ordered pre_install, install, post_install"
  }
}

run "scripts_output_install_only" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = output.scripts == ["harleylrn-kiro-cli-install_script"]
    error_message = "scripts output should only contain install when no pre/post scripts are set"
  }
}
