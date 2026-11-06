mock_provider "coder" {}

variables {
  agent_id = "test-agent"

  coder_app_icon         = "/icon/code.svg"
  coder_app_slug         = "test-ide"
  coder_app_display_name = "Test IDE"

  protocol   = "test-ide"
  config_dir = "$HOME/.test-ide"
}

run "defaults_create_no_extension_script" {
  command = plan

  assert {
    condition     = length(coder_script.install_extensions) == 0
    error_message = "Default inputs must not create an extension installation script."
  }

  assert {
    condition     = length(coder_script.apply_settings) == 0
    error_message = "Default inputs must not create a settings script."
  }
}

run "settings_create_one_blocking_script" {
  command = plan

  variables {
    settings = {
      "editor.fontSize" = 14
    }
    settings_file = "$HOME/.test-ide-server/data/Machine/settings.json"
  }

  assert {
    condition     = length(coder_script.apply_settings) == 1
    error_message = "Configured settings must create one settings script."
  }

  assert {
    condition     = coder_script.apply_settings[0].start_blocks_login
    error_message = "Settings must be applied before ordinary workspace login."
  }

  assert {
    condition     = coder_script.apply_settings[0].timeout == 300
    error_message = "The settings script must have a finite timeout."
  }
}

run "settings_require_wrapper_path" {
  command = plan

  variables {
    settings = {
      "editor.fontSize" = 14
    }
  }

  expect_failures = [
    coder_script.apply_settings,
  ]
}

run "settings_reject_non_object_input" {
  command = plan

  variables {
    settings = ["editor.fontSize"]
  }

  expect_failures = [
    var.settings,
  ]
}

run "extensions_create_one_blocking_script" {
  command = plan

  variables {
    extensions     = ["ms-python.python"]
    extensions_dir = "$HOME/.test-ide-server/extensions"
    ide_cli_path   = "$HOME/.coder-modules/coder/test-ide/server/bin/test-ide-server"
  }

  assert {
    condition     = length(coder_script.install_extensions) == 1
    error_message = "Extensions must create one installation script."
  }

  assert {
    condition     = coder_script.install_extensions[0].start_blocks_login
    error_message = "The finite extension installation script must block ordinary login by default."
  }

  assert {
    condition     = coder_script.install_extensions[0].timeout == 1800
    error_message = "The extension installation script must have a finite timeout."
  }

  assert {
    condition     = !strcontains(coder_script.install_extensions[0].script, "--force")
    error_message = "Extension installation must not force updates on every workspace start."
  }
}

run "extensions_reject_empty_entries" {
  command = plan

  variables {
    extensions     = [""]
    extensions_dir = "$HOME/.test-ide-server/extensions"
    ide_cli_path   = "$HOME/.coder-modules/coder/test-ide/server/bin/test-ide-server"
  }

  expect_failures = [
    var.extensions,
  ]
}
