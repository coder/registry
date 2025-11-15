run "required_vars" {
  command = plan

  variables {
    agent_id               = "foo"
    coder_app_icon         = "/icon/code.svg"
    coder_app_slug         = "vscode"
    coder_app_display_name = "VS Code Desktop"
    protocol               = "vscode"
  }
}

run "default_extensions_dir_vscode" {
  command = plan

  variables {
    agent_id               = "foo"
    coder_app_icon         = "/icon/code.svg"
    coder_app_slug         = "vscode"
    coder_app_display_name = "VS Code Desktop"
    protocol               = "vscode"
    extensions             = ["ms-python.python"]
  }

  assert {
    condition     = local.final_extensions_dir == "~/.vscode-server/extensions"
    error_message = "Default extensions directory for vscode should be ~/.vscode-server/extensions"
  }
}

run "default_extensions_dir_vscodium" {
  command = plan

  variables {
    agent_id               = "foo"
    coder_app_icon         = "/icon/code.svg"
    coder_app_slug         = "vscodium"
    coder_app_display_name = "VSCodium"
    protocol               = "vscodium"
    extensions             = ["ms-python.python"]
  }

  assert {
    condition     = local.final_extensions_dir == "~/.vscode-server-oss/extensions"
    error_message = "Default extensions directory for vscodium should be ~/.vscode-server-oss/extensions"
  }
}

run "custom_extensions_dir_override" {
  command = plan

  variables {
    agent_id               = "foo"
    coder_app_icon         = "/icon/code.svg"
    coder_app_slug         = "vscode"
    coder_app_display_name = "VS Code Desktop"
    protocol               = "vscode"
    extensions_dir         = "/custom/extensions/path"
    extensions             = ["ms-python.python"]
  }

  assert {
    condition     = local.final_extensions_dir == "/custom/extensions/path"
    error_message = "Custom extensions directory should override default"
  }
}

run "invalid_protocol_validation" {
  command = plan

  variables {
    agent_id               = "foo"
    coder_app_icon         = "/icon/code.svg"
    coder_app_slug         = "invalid"
    coder_app_display_name = "Invalid IDE"
    protocol               = "invalid"
  }

  expect_failures = [
    var.protocol
  ]
}

run "mutual_exclusion_validation" {
  command = plan

  variables {
    agent_id               = "foo"
    coder_app_icon         = "/icon/code.svg"
    coder_app_slug         = "vscode"
    coder_app_display_name = "VS Code Desktop"
    protocol               = "vscode"
    extensions             = ["ms-python.python"]
    extensions_urls        = ["https://marketplace.visualstudio.com/test.vsix"]
  }

  expect_failures = [
    resource.coder_script.extensions-installer
  ]
}
