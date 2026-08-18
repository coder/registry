mock_provider "coder" {}

variables {
  agent_id = "test-agent-id"
}

run "defaults" {
  command = plan

  assert {
    condition     = resource.coder_script.personalize.agent_id == "test-agent-id"
    error_message = "Personalize must use the configured agent ID."
  }

  assert {
    condition     = resource.coder_script.personalize.log_path == "~/personalize.log"
    error_message = "Personalize must preserve the default log path."
  }

  assert {
    condition     = resource.coder_script.personalize.run_on_start
    error_message = "Personalize must run when the workspace starts."
  }

  assert {
    condition     = resource.coder_script.personalize.start_blocks_login
    error_message = "Personalize must continue to block login until it finishes."
  }
}

run "custom_paths" {
  command = plan

  variables {
    path     = "/tmp/personalize scripts/$(printf injected) [daily]*"
    log_path = "/tmp/personalize logs/start.log"
  }

  assert {
    condition     = resource.coder_script.personalize.log_path == var.log_path
    error_message = "Personalize must use the configured log path."
  }

  assert {
    condition     = strcontains(resource.coder_script.personalize.script, base64encode(var.path))
    error_message = "The rendered script must contain the encoded custom path."
  }

  assert {
    condition     = !strcontains(resource.coder_script.personalize.script, var.path)
    error_message = "The rendered script must not interpolate the raw custom path."
  }
}
