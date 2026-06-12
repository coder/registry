run "required_variables" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }
}

run "default_terminal_mode" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }

  assert {
    condition     = resource.coder_app.zellij_terminal[0].command == "zellij attach --create default"
    error_message = "Terminal mode should use 'zellij attach --create default' command"
  }

  assert {
    condition     = resource.coder_app.zellij_terminal[0].slug == "zellij"
    error_message = "Terminal app slug should be 'zellij'"
  }

  assert {
    condition     = resource.coder_app.zellij_terminal[0].display_name == "Zellij"
    error_message = "Terminal app display name should be 'Zellij'"
  }

  assert {
    condition     = length(resource.coder_app.zellij_web) == 0
    error_message = "Web app should not be created in terminal mode"
  }
}

run "web_mode" {
  command = plan

  variables {
    agent_id = "test-agent-id"
    mode     = "web"
  }

  assert {
    condition     = resource.coder_app.zellij_web[0].url == "http://localhost:8082"
    error_message = "Web app should use default port 8082"
  }

  assert {
    condition     = resource.coder_app.zellij_web[0].subdomain == true
    error_message = "Web app should use subdomain"
  }

  assert {
    condition     = resource.coder_app.zellij_web[0].slug == "zellij"
    error_message = "Web app slug should be 'zellij'"
  }

  assert {
    condition     = length(resource.coder_app.zellij_terminal) == 0
    error_message = "Terminal app should not be created in web mode"
  }
}

run "web_mode_custom_port" {
  command = plan

  variables {
    agent_id = "test-agent-id"
    mode     = "web"
    web_port = 9090
  }

  assert {
    condition     = resource.coder_app.zellij_web[0].url == "http://localhost:9090"
    error_message = "Web app should use custom port 9090"
  }
}

run "custom_order_and_group" {
  command = plan

  variables {
    agent_id = "test-agent-id"
    order    = 3
    group    = "Terminal"
  }

  assert {
    condition     = resource.coder_app.zellij_terminal[0].order == 3
    error_message = "App order should be 3"
  }

  assert {
    condition     = resource.coder_app.zellij_terminal[0].group == "Terminal"
    error_message = "App group should be 'Terminal'"
  }
}

run "custom_icon" {
  command = plan

  variables {
    agent_id = "test-agent-id"
    icon     = "/icon/custom.svg"
  }

  assert {
    condition     = resource.coder_app.zellij_terminal[0].icon == "/icon/custom.svg"
    error_message = "App should use custom icon"
  }
}

run "coder_script_config" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }

  assert {
    condition     = resource.coder_script.zellij.display_name == "Zellij"
    error_message = "Script display name should be 'Zellij'"
  }

  assert {
    condition     = resource.coder_script.zellij.run_on_start == true
    error_message = "Script should run on start"
  }

  assert {
    condition     = resource.coder_script.zellij.run_on_stop == false
    error_message = "Script should not run on stop"
  }
}
