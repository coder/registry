mock_provider "coder" {}

variables {
  agent_id = "test-agent"
}

run "defaults_preserve_vscode_uri" {
  command = plan

  assert {
    condition     = startswith(output.vscode_url, "vscode://coder.coder-remote/open")
    error_message = "The default app URL must keep the vscode protocol."
  }
}

run "extensions_accept_remote_ids" {
  command = plan

  variables {
    extensions = [
      "ms-python.python",
      "esbenp.prettier-vscode@12.4.0",
    ]
  }

  assert {
    condition     = length(var.extensions) == 2
    error_message = "The VS Code Desktop wrapper must accept configured extension IDs."
  }
}

run "extensions_reject_empty_ids" {
  command = plan

  variables {
    extensions = [""]
  }

  expect_failures = [
    var.extensions,
  ]
}

run "settings_defaults_create_no_script" {
  command = plan

  assert {
    condition     = length(coder_script.apply_settings) == 0
    error_message = "Default inputs must not create a settings script."
  }
}

run "settings_create_script" {
  command = plan

  variables {
    settings = {
      "editor.fontSize" = 14
    }
  }

  assert {
    condition     = length(coder_script.apply_settings) == 1
    error_message = "Configured settings must create one settings script."
  }

  assert {
    condition     = coder_script.apply_settings[0].start_blocks_login
    error_message = "Settings script must block login by default."
  }

  assert {
    condition     = coder_script.apply_settings[0].timeout == 300
    error_message = "Settings script must have a finite timeout."
  }
}
