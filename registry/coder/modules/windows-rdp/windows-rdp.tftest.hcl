mock_provider "coder" {}

run "native_rdp_disabled_by_default" {
  command = plan

  variables {
    agent_id = "test-agent"
  }

  assert {
    condition     = length(coder_app.native-rdp) == 0
    error_message = "The native RDP app must remain disabled by default."
  }

  assert {
    condition     = length(data.coder_workspace.me) == 0
    error_message = "The workspace data source must not be read when native RDP is disabled."
  }
}

run "native_rdp_enabled" {
  command = plan

  variables {
    agent_id          = "test-agent"
    agent_name        = "windows-agent"
    enable_native_rdp = true
    admin_username    = "RDP User"
    admin_password    = "N;JVO*U\\mL^a*P\"'`$&<>|#%+"
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
    error_message = "Enabling native RDP must create exactly one app."
  }

  assert {
    condition     = coder_app.native-rdp[0].external
    error_message = "The native RDP app must open through an external URI handler."
  }

  assert {
    condition     = coder_app.native-rdp[0].url == "coder://coder.example.com/v0/open/ws/windows-workspace/agent/${var.agent_name}/rdp?username=${urlencode(var.admin_username)}&password=${urlencode(var.admin_password)}"
    error_message = "The native RDP app must target the selected agent and URL-encode both credentials."
  }
}
