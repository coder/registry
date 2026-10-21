run "test_defaults_preserve_workspace_configuration" {
  command = plan

  variables {
    agent_id                 = "test-agent-id"
    jfrog_url                = "http://127.0.0.1:1"
    artifactory_access_token = "admin-token"
    check_license            = false
  }

  override_data {
    target = data.coder_workspace_owner.me
    values = {
      email = "coder@example.com"
      name  = "coder"
    }
  }

  assert {
    condition     = length(resource.coder_script.jfrog) == 1 && resource.coder_script.jfrog[0].run_on_start
    error_message = "default settings should create the workspace configuration script"
  }
}

run "test_access_token_only" {
  command = plan

  variables {
    agent_id                 = "test-agent-id"
    jfrog_url                = "http://127.0.0.1:1"
    artifactory_access_token = "admin-token"
    check_license            = false
    install_jfrog_cli        = false
    configure_jfrog_cli      = false
  }

  override_data {
    target = data.coder_workspace_owner.me
    values = {
      email = "coder@example.com"
      name  = "coder"
    }
  }

  assert {
    condition     = length(resource.coder_script.jfrog) == 0
    error_message = "token-only mode should not create the workspace configuration script"
  }

  assert {
    condition     = length(resource.coder_env.goproxy) == 0
    error_message = "token-only mode should not configure package managers"
  }
}

run "test_package_manager_only" {
  command = plan

  variables {
    agent_id                 = "test-agent-id"
    jfrog_url                = "http://127.0.0.1:1"
    artifactory_access_token = "admin-token"
    check_license            = false
    install_jfrog_cli        = false
    configure_jfrog_cli      = false
    package_managers = {
      go = ["go"]
    }
  }

  override_data {
    target = data.coder_workspace_owner.me
    values = {
      email = "coder@example.com"
      name  = "coder"
    }
  }

  assert {
    condition     = length(resource.coder_script.jfrog) == 1
    error_message = "package manager configuration should create the workspace configuration script"
  }

  assert {
    condition     = length(resource.coder_env.goproxy) == 1
    error_message = "go package manager configuration should set GOPROXY"
  }
}
