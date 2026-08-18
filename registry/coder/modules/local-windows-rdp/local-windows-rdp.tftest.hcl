run "plan_with_defaults" {
  command = plan

  variables {
    agent_id   = "test-agent-id"
    agent_name = "main"
  }

  assert {
    condition     = strcontains(resource.coder_script.rdp_setup.script, "$password = 'coderRDP!'")
    error_message = "The default password should use a PowerShell single-quoted string."
  }

  assert {
    condition     = endswith(resource.coder_app.rdp_desktop.url, "username=Administrator&password=coderRDP%21")
    error_message = "The default app URL should encode its credentials."
  }
}

run "plan_with_special_characters" {
  command = plan

  variables {
    agent_id   = "test-agent-id"
    agent_name = "main"
    password   = "N;JVO*U\\mL^a*P\"'`$&<>|#%+"
  }

  # A PowerShell single-quoted string is literal except for the single quote,
  # which is escaped by doubling it.
  assert {
    condition     = strcontains(resource.coder_script.rdp_setup.script, format("$password = '%s'", replace(var.password, "'", "''")))
    error_message = "The setup script should preserve special characters in the password."
  }

  # Without encoding, the password truncates at the first & and drops
  # everything after a #.
  assert {
    condition     = endswith(resource.coder_app.rdp_desktop.url, "username=${urlencode(var.username)}&password=${urlencode(var.password)}")
    error_message = "The app URL should encode each credential parameter."
  }
}
