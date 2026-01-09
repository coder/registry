run "test_parsec_defaults" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }

  assert {
    condition     = coder_script.parsec.display_name == "Parsec Installation"
    error_message = "Display name should be 'Parsec Installation'"
  }

  assert {
    condition     = coder_script.parsec.run_on_start == true
    error_message = "Script should run on start"
  }
}

run "test_parsec_custom_display_name" {
  command = plan

  variables {
    agent_id     = "test-agent-id"
    display_name = "Custom Parsec"
  }

  assert {
    condition     = coder_app.parsec_docs.display_name == "Parsec Docs"
    error_message = "Docs app display name should be 'Parsec Docs'"
  }
}

run "test_parsec_headless_disabled" {
  command = plan

  variables {
    agent_id = "test-agent-id"
    headless = false
  }

  assert {
    condition     = var.headless == false
    error_message = "Headless should be false"
  }
}
