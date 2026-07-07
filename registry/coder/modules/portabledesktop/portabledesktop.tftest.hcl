run "plan_with_required_vars" {
  command = plan

  variables {
    agent_id = "example-agent-id"
  }
}

run "plan_with_custom_install_dir" {
  command = plan

  variables {
    agent_id    = "example-agent-id"
    install_dir = "/opt/bin"
  }

  assert {
    condition     = resource.coder_script.portabledesktop.display_name == "Portable Desktop"
    error_message = "Expected coder_script resource to have correct display name"
  }
}

run "plan_with_custom_url" {
  command = plan

  variables {
    agent_id = "example-agent-id"
    url      = "https://example.com/custom-portabledesktop"
    sha256   = "abc123"
  }

  assert {
    condition     = resource.coder_script.portabledesktop.run_on_start == true
    error_message = "Expected coder_script to run on start"
  }
}
