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

run "cli_scripts_and_healthcheck" {
  command = plan
  variables {
    agent_id       = "foo"
    accept_license = true
    use_cli        = true
  }
  assert {
    condition     = length(coder_script.vscode-web) == 0 && length(module.cli) == 1
    error_message = "CLI mode must replace the legacy startup script."
  }
  assert {
    condition     = local.healthcheck_url == "http://localhost:13338/"
    error_message = "The CLI proxy must be probed at its root route."
  }
  assert {
    condition     = length(output.scripts) == 2
    error_message = "CLI mode must expose installation and startup synchronization names."
  }
}

run "legacy_path_routing" {
  command = plan
  variables {
    agent_id       = "foo"
    accept_license = true
    subdomain      = false
    disable_trust  = true
    extensions_dir = "/home/coder/custom extensions"
  }
  assert {
    condition     = length(coder_script.vscode-web) == 1 && length(module.cli) == 0
    error_message = "Existing configurations must retain the legacy launch mode."
  }
}

run "cli_rejects_shared_origin" {
  command = plan
  variables {
    agent_id       = "foo"
    accept_license = true
    use_cli        = true
    subdomain      = false
  }
  expect_failures = [coder_app.vscode-web]
}

run "cli_accepts_server_options_together" {
  command = plan
  variables {
    agent_id       = "foo"
    accept_license = true
    use_cli        = true
    disable_trust  = true
    extensions_dir = "/home/coder/custom extensions"
    platform       = "linux"
  }

  assert {
    condition     = length(module.cli) == 1 && length(coder_script.vscode-web) == 0
    error_message = "All three server options must work with the CLI launcher."
  }
}

run "cli_rejects_invalid_commit" {
  command = plan
  variables {
    agent_id       = "foo"
    accept_license = true
    use_cli        = true
    commit_id      = "not-a-commit"
  }
  expect_failures = [coder_app.vscode-web]
}

run "cli_rejects_offline_recommendations" {
  command = plan
  variables {
    agent_id                = "foo"
    accept_license          = true
    use_cli                 = true
    offline                 = true
    auto_install_extensions = true
  }
  expect_failures = [coder_app.vscode-web]
}

run "cli_rejects_windows_server" {
  command = plan
  variables {
    agent_id       = "foo"
    accept_license = true
    use_cli        = true
    platform       = "win32"
  }
  expect_failures = [coder_app.vscode-web]
}

run "cli_rejects_offline_extensions" {
  command = plan
  variables {
    agent_id       = "foo"
    accept_license = true
    use_cli        = true
    offline        = true
    extensions     = ["publisher.extension"]
  }
  expect_failures = [coder_app.vscode-web]
}

run "cli_rejects_offline_and_cached" {
  command = plan
  variables {
    agent_id       = "foo"
    accept_license = true
    use_cli        = true
    offline        = true
    use_cached     = true
  }
  expect_failures = [coder_app.vscode-web]
}

run "cli_rejects_folder_and_workspace" {
  command = plan
  variables {
    agent_id       = "foo"
    accept_license = true
    use_cli        = true
    folder         = "/project"
    workspace      = "/project.code-workspace"
  }
  expect_failures = [coder_app.vscode-web]
}
