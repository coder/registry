run "default_output" {
  command = apply

  variables {
    agent_id = "foo"
  }

  override_data {
    target = data.coder_workspace.me
    values = {
      name = "default"
    }
  }

  override_data {
    target = data.coder_workspace_owner.me
    values = {
      name = "default"
    }
  }

  assert {
    condition     = output.zed_url == "zed://ssh/default.coder"
    error_message = "zed_url did not match expected default URL"
  }
}

run "adds_folder" {
  command = apply

  variables {
    agent_id = "foo"
    folder   = "/foo/bar"
  }

  override_data {
    target = data.coder_workspace.me
    values = {
      name = "default"
    }
  }

  override_data {
    target = data.coder_workspace_owner.me
    values = {
      name = "default"
    }
  }

  assert {
    condition     = output.zed_url == "zed://ssh/default.coder/foo/bar"
    error_message = "zed_url did not include provided folder path"
  }
}

run "adds_agent_name" {
  command = apply

  variables {
    agent_id   = "foo"
    agent_name = "myagent"
  }

  override_data {
    target = data.coder_workspace.me
    values = {
      name = "default"
    }
  }

  override_data {
    target = data.coder_workspace_owner.me
    values = {
      name = "default"
    }
  }

  assert {
    condition     = output.zed_url == "zed://ssh/myagent.default.default.coder"
    error_message = "zed_url did not include agent_name in hostname"
  }
}

run "settings_base64_encoding" {
  command = apply

  variables {
    agent_id = "foo"
    settings = jsonencode({
      theme    = "dark"
      fontSize = 14
    })
  }

  # Verify settings are base64 encoded (eyJ = base64 prefix for JSON starting with {")
  assert {
    condition     = can(regex("SETTINGS_B64='eyJ", coder_script.zed_settings.script))
    error_message = "settings should be base64 encoded in the script"
  }
}

run "empty_settings" {
  command = apply

  variables {
    agent_id = "foo"
    settings = ""
  }

  assert {
    condition     = can(regex("SETTINGS_B64=''", coder_script.zed_settings.script))
    error_message = "empty settings should result in empty SETTINGS_B64"
  }
}
