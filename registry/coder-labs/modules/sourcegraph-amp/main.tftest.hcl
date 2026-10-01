run "defaults_are_correct" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = var.install_amp == true
    error_message = "install_amp should default to true"
  }

  assert {
    condition     = var.amp_version == ""
    error_message = "amp_version should default to empty (latest)"
  }

  assert {
    condition     = local.workdir == ""
    error_message = "workdir should be empty by default"
  }

  assert {
    condition     = local.module_dir_name == ".coder-modules/coder-labs/sourcegraph-amp"
    error_message = "module_dir_name should be '.coder-modules/coder-labs/sourcegraph-amp'"
  }

  assert {
    condition     = length(coder_env.amp_api_key) == 0
    error_message = "AMP_API_KEY should not be created when amp_api_key is empty"
  }

  assert {
    condition     = strcontains(local.install_script, "ARG_MANAGED_SETTINGS_JSON=$(echo -n '' | base64 -d)")
    error_message = "managed settings should be empty by default"
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
    agent_id    = "test-agent"
    amp_api_key = "sgamp_test-key"
  }

  assert {
    condition     = coder_env.amp_api_key[0].name == "AMP_API_KEY" && coder_env.amp_api_key[0].value == "sgamp_test-key"
    error_message = "AMP_API_KEY env var should be created with the provided key"
  }

  assert {
    condition     = !strcontains(local.install_script, nonsensitive(var.amp_api_key)) && !strcontains(local.install_script, base64encode(nonsensitive(var.amp_api_key)))
    error_message = "API key should not be rendered into the install script"
  }
}

run "amp_version_is_passed_through" {
  command = plan

  variables {
    agent_id    = "test-agent"
    amp_version = "0.0.1790769659-g954f35"
  }

  assert {
    condition     = strcontains(local.install_script, "ARG_AMP_VERSION='0.0.1790769659-g954f35'")
    error_message = "amp_version should be rendered into the install script"
  }
}

run "invalid_amp_version_fails" {
  command = plan

  variables {
    agent_id    = "test-agent"
    amp_version = "1.0'; rm -rf /"
  }

  expect_failures = [
    var.amp_version,
  ]
}

run "invalid_mcp_fails" {
  command = plan

  variables {
    agent_id = "test-agent"
    mcp      = "[\"not-an-object\"]"
  }

  expect_failures = [
    var.mcp,
  ]
}

run "invalid_amp_settings_fails" {
  command = plan

  variables {
    agent_id     = "test-agent"
    amp_settings = "not json"
  }

  expect_failures = [
    var.amp_settings,
  ]
}

run "amp_settings_rejects_mcp_servers" {
  command = plan

  variables {
    agent_id     = "test-agent"
    amp_settings = "{\"amp.mcpServers\": {}}"
  }

  expect_failures = [
    var.amp_settings,
  ]
}

run "managed_settings_are_encoded" {
  command = plan

  variables {
    agent_id = "test-agent"
    managed_settings = {
      "amp.updates.mode" = "disabled"
    }
  }

  assert {
    condition     = strcontains(local.install_script, base64encode(jsonencode({ "amp.updates.mode" = "disabled" })))
    error_message = "managed_settings should be rendered base64-encoded into the install script"
  }
}

run "scripts_output_is_ordered" {
  command = plan

  variables {
    agent_id            = "test-agent"
    pre_install_script  = "echo pre"
    post_install_script = "echo post"
  }

  assert {
    condition     = output.scripts == ["coder-labs-sourcegraph-amp-pre_install_script", "coder-labs-sourcegraph-amp-install_script", "coder-labs-sourcegraph-amp-post_install_script"]
    error_message = "scripts output should be ordered pre_install, install, post_install"
  }
}

run "scripts_output_install_only" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = output.scripts == ["coder-labs-sourcegraph-amp-install_script"]
    error_message = "scripts output should only contain install when no pre/post scripts are set"
  }
}
