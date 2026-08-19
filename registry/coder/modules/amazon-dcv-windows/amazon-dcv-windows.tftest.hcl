run "plan_with_defaults" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }

  assert {
    condition     = resource.coder_app.web-dcv.url == "https://localhost:8443/?username=Administrator&password=coderDCV%21"
    error_message = "The default DCV app URL should preserve its credentials."
  }

  assert {
    condition     = strcontains(resource.coder_script.install-dcv.script, "$adminPassword = 'coderDCV!'")
    error_message = "The default password should use a PowerShell single-quoted string."
  }
}

run "plan_with_special_characters" {
  command = plan

  variables {
    agent_id       = "test-agent-id"
    admin_password = "N;JVO*U\\mL^a*P\"'`$&<>|#%+"
  }

  assert {
    condition     = endswith(resource.coder_app.web-dcv.url, "username=Administrator&password=${urlencode(var.admin_password)}")
    error_message = "The DCV app URL should encode each credential parameter."
  }

  assert {
    condition     = strcontains(resource.coder_script.install-dcv.script, format("$adminPassword = '%s'", replace(var.admin_password, "'", "''")))
    error_message = "The PowerShell script should preserve special characters."
  }
}
