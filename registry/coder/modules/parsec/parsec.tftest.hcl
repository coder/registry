# Test that the module initializes correctly with required variables
run "parsec_basic_test" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }

  assert {
    condition     = coder_script.parsec.display_name == "Parsec"
    error_message = "Parsec script display name should be 'Parsec'"
  }

  assert {
    condition     = coder_script.parsec.run_on_start == true
    error_message = "Parsec script should run on start"
  }

  assert {
    condition     = coder_app.parsec.display_name == "Parsec"
    error_message = "Parsec app display name should be 'Parsec'"
  }

  assert {
    condition     = coder_app.parsec.external == true
    error_message = "Parsec app should be external"
  }

  assert {
    condition     = coder_app.parsec.url == "https://web.parsec.app/"
    error_message = "Parsec app URL should be https://web.parsec.app/"
  }
}

# Test custom display name and slug
run "parsec_custom_name_test" {
  command = plan

  variables {
    agent_id     = "test-agent-id"
    display_name = "Cloud Gaming"
    slug         = "cloud-gaming"
  }

  assert {
    condition     = coder_app.parsec.display_name == "Cloud Gaming"
    error_message = "Custom display name should be applied"
  }

  assert {
    condition     = coder_app.parsec.slug == "cloud-gaming"
    error_message = "Custom slug should be applied"
  }
}

# Test that docs app is created
run "parsec_docs_app_test" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }

  assert {
    condition     = coder_app.parsec-docs.display_name == "Parsec Docs"
    error_message = "Parsec docs app should be created"
  }

  assert {
    condition     = coder_app.parsec-docs.url == "https://support.parsec.app/hc/en-us"
    error_message = "Parsec docs URL should point to support site"
  }

  assert {
    condition     = coder_app.parsec-docs.external == true
    error_message = "Parsec docs app should be external"
  }
}

# Test default values
run "parsec_defaults_test" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }

  assert {
    condition     = coder_app.parsec.slug == "parsec"
    error_message = "Default slug should be 'parsec'"
  }

  assert {
    condition     = coder_app.parsec.icon == "/icon/parsec.svg"
    error_message = "Default icon should be /icon/parsec.svg"
  }
}
