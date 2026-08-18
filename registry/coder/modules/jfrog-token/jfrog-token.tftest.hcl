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
    condition     = resource.coder_script.jfrog.run_on_start
    error_message = "default settings should preserve the running workspace configuration script"
  }
}

run "test_access_token_only" {
  command = plan

  variables {
    agent_id                   = "test-agent-id"
    jfrog_url                  = "http://127.0.0.1:1"
    artifactory_access_token   = "admin-token"
    check_license              = false
    install_jfrog_cli          = false
    configure_jfrog_cli        = false
    configure_package_managers = false
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
    condition     = !resource.coder_script.jfrog.run_on_start
    error_message = "token-only mode should not run the workspace configuration script"
  }

  assert {
    condition     = length(resource.coder_env.goproxy) == 0
    error_message = "token-only mode should not configure package managers"
  }
}
