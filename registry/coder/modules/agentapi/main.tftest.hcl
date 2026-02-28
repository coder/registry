# Test agentapi module with default settings (enable_agentapi = true)
run "test_agentapi_defaults" {
  command = plan

  variables {
    agent_id             = "test-agent-id"
    agent_name           = "claude"
    module_dir_name      = ".agentapi-module"
    web_app_display_name = "AgentAPI Web"
    web_app_slug         = "agentapi-web"
    web_app_icon         = "/icon/coder.svg"
    cli_app_display_name = "AgentAPI CLI"
    cli_app_slug         = "agentapi-cli"
    install_script       = "echo 'install'"
    start_script         = "echo 'start'"
  }

  assert {
    condition     = length(coder_script.agentapi) == 1
    error_message = "AgentAPI script should be created when enable_agentapi is true"
  }

  assert {
    condition     = coder_script.agentapi[0].agent_id == "test-agent-id"
    error_message = "AgentAPI script agent ID should match input"
  }

  assert {
    condition     = coder_script.agentapi[0].display_name == "Start AgentAPI"
    error_message = "AgentAPI script should have correct display name"
  }

  assert {
    condition     = coder_script.agentapi[0].run_on_start == true
    error_message = "AgentAPI script should run on start"
  }

  assert {
    condition     = length(coder_script.agentapi_shutdown) == 1
    error_message = "AgentAPI shutdown script should be created when enable_agentapi is true"
  }

  assert {
    condition     = coder_script.agentapi_shutdown[0].run_on_stop == true
    error_message = "AgentAPI shutdown script should run on stop"
  }

  assert {
    condition     = length(coder_app.agentapi_web) == 1
    error_message = "AgentAPI web app should be created when enable_agentapi is true"
  }

  assert {
    condition     = coder_app.agentapi_web[0].slug == "agentapi-web"
    error_message = "AgentAPI web app slug should match input"
  }

  assert {
    condition     = coder_app.agentapi_web[0].subdomain == true
    error_message = "AgentAPI web app should use subdomain by default"
  }

  assert {
    condition     = length(coder_app.agent_cli) == 0
    error_message = "CLI app should not be created by default"
  }
}

# Test with enable_agentapi = false
run "test_agentapi_disabled" {
  command = plan

  variables {
    agent_id             = "test-agent-id"
    agent_name           = "claude"
    module_dir_name      = ".agentapi-module"
    web_app_display_name = "AgentAPI Web"
    web_app_slug         = "agentapi-web"
    web_app_icon         = "/icon/coder.svg"
    cli_app_display_name = "AgentAPI CLI"
    cli_app_slug         = "agentapi-cli"
    install_script       = "echo 'install'"
    start_script         = "echo 'start'"
    enable_agentapi      = false
  }

  assert {
    condition     = length(coder_script.agentapi) == 0
    error_message = "AgentAPI script should not be created when enable_agentapi is false"
  }

  assert {
    condition     = length(coder_script.agentapi_shutdown) == 0
    error_message = "AgentAPI shutdown script should not be created when enable_agentapi is false"
  }

  assert {
    condition     = length(coder_app.agentapi_web) == 0
    error_message = "AgentAPI web app should not be created when enable_agentapi is false"
  }
}

# Test with CLI app enabled
run "test_cli_app_enabled" {
  command = plan

  variables {
    agent_id             = "test-agent-id"
    agent_name           = "claude"
    module_dir_name      = ".agentapi-module"
    web_app_display_name = "AgentAPI Web"
    web_app_slug         = "agentapi-web"
    web_app_icon         = "/icon/coder.svg"
    cli_app_display_name = "AgentAPI CLI"
    cli_app_slug         = "agentapi-cli"
    install_script       = "echo 'install'"
    start_script         = "echo 'start'"
    cli_app              = true
  }

  assert {
    condition     = length(coder_app.agent_cli) == 1
    error_message = "CLI app should be created when cli_app is true"
  }

  assert {
    condition     = coder_app.agent_cli[0].slug == "agentapi-cli"
    error_message = "CLI app slug should match input"
  }

  assert {
    condition     = coder_app.agent_cli[0].display_name == "AgentAPI CLI"
    error_message = "CLI app display name should match input"
  }
}

# Test custom port
run "test_custom_port" {
  command = plan

  variables {
    agent_id             = "test-agent-id"
    agent_name           = "claude"
    module_dir_name      = ".agentapi-module"
    web_app_display_name = "AgentAPI Web"
    web_app_slug         = "agentapi-web"
    web_app_icon         = "/icon/coder.svg"
    cli_app_display_name = "AgentAPI CLI"
    cli_app_slug         = "agentapi-cli"
    install_script       = "echo 'install'"
    start_script         = "echo 'start'"
    agentapi_port        = 4000
  }

  assert {
    condition     = coder_app.agentapi_web[0].url == "http://localhost:4000/"
    error_message = "AgentAPI web app URL should use custom port"
  }

  assert {
    condition     = one([for h in coder_app.agentapi_web[0].healthcheck : h.url]) == "http://localhost:4000/status"
    error_message = "AgentAPI healthcheck URL should use custom port"
  }
}

# Test subdomain false validation rejects old versions
run "test_subdomain_false_rejects_old_version" {
  command = plan

  variables {
    agent_id             = "test-agent-id"
    agent_name           = "claude"
    module_dir_name      = ".agentapi-module"
    web_app_display_name = "AgentAPI Web"
    web_app_slug         = "agentapi-web"
    web_app_icon         = "/icon/coder.svg"
    cli_app_display_name = "AgentAPI CLI"
    cli_app_slug         = "agentapi-cli"
    install_script       = "echo 'install'"
    start_script         = "echo 'start'"
    agentapi_subdomain   = false
    agentapi_version     = "v0.3.2"
  }

  expect_failures = [
    var.agentapi_subdomain,
  ]
}

# Test subdomain false with valid version
run "test_subdomain_false_allows_valid_version" {
  command = plan

  variables {
    agent_id             = "test-agent-id"
    agent_name           = "claude"
    module_dir_name      = ".agentapi-module"
    web_app_display_name = "AgentAPI Web"
    web_app_slug         = "agentapi-web"
    web_app_icon         = "/icon/coder.svg"
    cli_app_display_name = "AgentAPI CLI"
    cli_app_slug         = "agentapi-cli"
    install_script       = "echo 'install'"
    start_script         = "echo 'start'"
    agentapi_subdomain   = false
    agentapi_version     = "v0.3.3"
  }

  assert {
    condition     = coder_app.agentapi_web[0].subdomain == false
    error_message = "AgentAPI web app should not use subdomain"
  }
}
