# Test for boundary module

run "plan_with_required_vars" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }

  # Verify the coder_env resource is created with correct agent_id
  assert {
    condition     = coder_env.boundary_wrapper_path.agent_id == "test-agent-id"
    error_message = "boundary_wrapper_path agent_id should match the input variable"
  }

  assert {
    condition     = coder_env.boundary_wrapper_path.name == "BOUNDARY_WRAPPER_PATH"
    error_message = "Environment variable name should be 'BOUNDARY_WRAPPER_PATH'"
  }

  assert {
    condition     = coder_env.boundary_wrapper_path.value == "$HOME/.coder-modules/coder/boundary/scripts/boundary-wrapper.sh"
    error_message = "Environment variable value should be the boundary wrapper path"
  }

  # Verify the boundary_wrapper_path output
  assert {
    condition     = output.boundary_wrapper_path == "$HOME/.coder-modules/coder/boundary/scripts/boundary-wrapper.sh"
    error_message = "boundary_wrapper_path output should be correct"
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
    agent_id                     = "test-agent-id"
    compile_boundary_from_source = true
    boundary_version             = "main"
  }

  assert {
    condition     = coder_env.boundary_wrapper_path.agent_id == "test-agent-id"
    error_message = "boundary_wrapper_path agent_id should match the input variable"
  }

  assert {
    condition     = output.boundary_wrapper_path == "$HOME/.coder-modules/coder/boundary/scripts/boundary-wrapper.sh"
    error_message = "boundary_wrapper_path output should be correct"
  }

  assert {
    condition     = contains(output.scripts, "coder-boundary-install_script")
    error_message = "scripts should contain the install script name"
  }
}

run "plan_with_use_directly" {
  command = plan

  variables {
    agent_id              = "test-agent-id"
    use_boundary_directly = true
    boundary_version      = "latest"
  }

  assert {
    condition     = coder_env.boundary_wrapper_path.agent_id == "test-agent-id"
    error_message = "boundary_wrapper_path agent_id should match the input variable"
  }

  assert {
    condition     = output.boundary_wrapper_path == "$HOME/.coder-modules/coder/boundary/scripts/boundary-wrapper.sh"
    error_message = "boundary_wrapper_path output should be correct"
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
    condition     = coder_env.boundary_wrapper_path.agent_id == "test-agent-id"
    error_message = "boundary_wrapper_path agent_id should match the input variable"
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
    condition     = coder_env.boundary_wrapper_path.value == "$HOME/.coder-modules/custom/boundary/scripts/boundary-wrapper.sh"
    error_message = "Environment variable should use custom module directory"
  }

  assert {
    condition     = output.boundary_wrapper_path == "$HOME/.coder-modules/custom/boundary/scripts/boundary-wrapper.sh"
    error_message = "boundary_wrapper_path output should use custom module directory"
  }
}
