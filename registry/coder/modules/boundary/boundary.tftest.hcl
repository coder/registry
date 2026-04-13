# Test for boundary module

run "plan_with_required_vars" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }

  # Verify the coder_script resource is created with correct agent_id
  assert {
    condition     = coder_script.boundary_script.agent_id == "test-agent-id"
    error_message = "boundary_script agent_id should match the input variable"
  }

  assert {
    condition     = coder_script.boundary_script.display_name == "Boundary Installation Script"
    error_message = "display_name should be 'Boundary Installation Script'"
  }
}

run "plan_with_compile_from_source" {
  command = plan

  variables {
    agent_id                     = "test-agent-id"
    compile_boundary_from_source = true
    boundary_version             = "main"
  }

  assert {
    condition     = coder_script.boundary_script.agent_id == "test-agent-id"
    error_message = "boundary_script agent_id should match the input variable"
  }
}

run "plan_with_use_directly" {
  command = plan

  variables {
    agent_id             = "test-agent-id"
    use_boundary_directly = true
    boundary_version     = "latest"
  }

  assert {
    condition     = coder_script.boundary_script.agent_id == "test-agent-id"
    error_message = "boundary_script agent_id should match the input variable"
  }
}
