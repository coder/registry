run "default_open_in" {
  command = plan

  variables {
    agent_id       = "foo"
    accept_license = true
  }

  assert {
    condition     = resource.coder_app.vscode-web.open_in == "slim-window"
    error_message = "Default open_in value should be 'slim-window'."
  }
}

run "custom_open_in" {
  command = plan

  variables {
    agent_id       = "foo"
    accept_license = true
    open_in        = "tab"
  }

  assert {
    condition     = resource.coder_app.vscode-web.open_in == "tab"
    error_message = "Custom open_in value should be applied to the Coder app."
  }
}

run "invalid_open_in" {
  command = plan

  variables {
    agent_id       = "foo"
    accept_license = true
    open_in        = "invalid"
  }

  expect_failures = [
    var.open_in,
  ]
}
