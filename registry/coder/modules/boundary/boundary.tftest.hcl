# Test for boundary module

run "plan_with_required_vars" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }

  # Verify the agent_firewall_wrapper_path output
  assert {
    condition     = output.agent_firewall_wrapper_path == "$HOME/.coder-modules/coder/boundary/scripts/boundary-wrapper.sh"
    error_message = "agent_firewall_wrapper_path output should be correct"
  }

  # Verify agent_firewall_config_path output defaults to the managed path
  assert {
    condition     = output.agent_firewall_config_path == "$HOME/.coder-modules/coder/boundary/config/config.yaml"
    error_message = "agent_firewall_config_path output should default to managed config path"
  }

  # Verify the scripts output contains the install script name
  assert {
    condition     = contains(output.scripts, "coder-boundary-install_script")
    error_message = "scripts should contain the install script name"
  }
}

run "plan_with_compile_from_source" {
  command = plan

  variables {
    agent_id                           = "test-agent-id"
    compile_agent_firewall_from_source = true
    agent_firewall_version             = "main"
  }

  assert {
    condition     = output.agent_firewall_wrapper_path == "$HOME/.coder-modules/coder/boundary/scripts/boundary-wrapper.sh"
    error_message = "agent_firewall_wrapper_path output should be correct"
  }

  assert {
    condition     = contains(output.scripts, "coder-boundary-install_script")
    error_message = "scripts should contain the install script name"
  }
}

run "plan_with_use_directly" {
  command = plan

  variables {
    agent_id                    = "test-agent-id"
    use_agent_firewall_directly = true
    agent_firewall_version      = "latest"
  }

  assert {
    condition     = output.agent_firewall_wrapper_path == "$HOME/.coder-modules/coder/boundary/scripts/boundary-wrapper.sh"
    error_message = "agent_firewall_wrapper_path output should be correct"
  }

  assert {
    condition     = contains(output.scripts, "coder-boundary-install_script")
    error_message = "scripts should contain the install script name"
  }
}

run "plan_with_custom_hooks" {
  command = plan

  variables {
    agent_id            = "test-agent-id"
    pre_install_script  = "echo 'Before install'"
    post_install_script = "echo 'After install'"
  }

  assert {
    condition     = contains(output.scripts, "coder-boundary-install_script")
    error_message = "scripts should contain the install script name"
  }

  # Verify pre and post install script names are set
  assert {
    condition     = contains(output.scripts, "coder-boundary-pre_install_script")
    error_message = "scripts should contain the pre_install script name"
  }

  assert {
    condition     = contains(output.scripts, "coder-boundary-post_install_script")
    error_message = "scripts should contain the post_install script name"
  }
}

run "plan_with_custom_module_directory" {
  command = plan

  variables {
    agent_id         = "test-agent-id"
    module_directory = "$HOME/.coder-modules/custom/boundary"
  }

  assert {
    condition     = output.agent_firewall_wrapper_path == "$HOME/.coder-modules/custom/boundary/scripts/boundary-wrapper.sh"
    error_message = "agent_firewall_wrapper_path output should use custom module directory"
  }

  # Config path should also follow the module directory
  assert {
    condition     = output.agent_firewall_config_path == "$HOME/.coder-modules/custom/boundary/config/config.yaml"
    error_message = "agent_firewall_config_path output should use custom module directory"
  }
}

run "plan_with_inline_config" {
  command = plan

  variables {
    agent_id              = "test-agent-id"
    agent_firewall_config = "allowlist:\n  - domain=example.com\nlog_level: debug\n"
  }

  # Inline config should still point to the managed path.
  assert {
    condition     = output.agent_firewall_config_path == "$HOME/.coder-modules/coder/boundary/config/config.yaml"
    error_message = "agent_firewall_config_path output should point to managed config path"
  }
}

run "plan_with_config_path" {
  command = plan

  variables {
    agent_id                   = "test-agent-id"
    agent_firewall_config_path = "/workspace/my-boundary-config.yaml"
  }

  # agent_firewall_config_path output should point to the user-provided path.
  assert {
    condition     = output.agent_firewall_config_path == "/workspace/my-boundary-config.yaml"
    error_message = "agent_firewall_config_path output should point to user-provided path"
  }
}

run "plan_with_both_configs_should_fail" {
  command = plan

  variables {
    agent_id                   = "test-agent-id"
    agent_firewall_config      = "allowlist: []"
    agent_firewall_config_path = "/workspace/config.yaml"
  }

  expect_failures = [
    var.agent_firewall_config,
  ]
}
