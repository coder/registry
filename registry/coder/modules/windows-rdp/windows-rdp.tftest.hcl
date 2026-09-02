mock_provider "coder" {}

run "native_rdp_disabled" {
  command = plan

  variables {
    agent_id          = "test-agent"
    enable_native_rdp = false
  }

  assert {
    condition     = length(coder_app.native-rdp) == 0
    error_message = "Disabling native RDP must omit the native app."
  }

  assert {
    condition     = length(data.coder_workspace.me) == 0
    error_message = "The workspace data source must not be read when native RDP is disabled."
  }
}

run "native_rdp_requires_agent_name" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  override_data {
    target = data.coder_workspace.me
    values = {
      access_url = "https://coder.example.com"
      name       = "windows-workspace"
    }
  }

  expect_failures = [coder_app.native-rdp]
}

run "native_rdp_enabled_by_default" {
  command = plan

  variables {
    agent_id       = "test-agent"
    agent_name     = "windows-agent"
    admin_username = "RDP User"
    admin_password = "N;JVO*U\\mL^a*P\"'`$&<>|#%+"
  }

  override_data {
    target = data.coder_workspace.me
    values = {
      access_url = "https://coder.example.com"
      name       = "windows-workspace"
    }
  }

  assert {
    condition     = length(coder_app.native-rdp) == 1
    error_message = "Native RDP must create exactly one app by default."
  }

  assert {
    condition     = coder_app.native-rdp[0].external
    error_message = "The native RDP app must open through an external URI handler."
  }

  assert {
    condition     = coder_app.native-rdp[0].icon == "/icon/rdp.svg"
    error_message = "The native RDP app must use an icon distinct from Web RDP."
  }

  assert {
    condition     = coder_app.native-rdp[0].tooltip == var.tooltip
    error_message = "The native RDP app must explain its Coder Desktop dependency."
  }

  assert {
    condition     = coder_app.native-rdp[0].url == "coder://coder.example.com/v0/open/ws/windows-workspace/agent/${var.agent_name}/rdp?username=${urlencode(var.admin_username)}&password=${urlencode(var.admin_password)}"
    error_message = "The native RDP app must target the selected agent and URL-encode both credentials."
  }
}
