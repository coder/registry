run "defaults_to_auth_key_type" {
  command = plan

  variables {
    agent_id = "test-agent-id"
  }

  assert {
    condition     = strcontains(coder_script.github_upload_public_key.script, "KEY_TYPE='auth'")
    error_message = "key_type should default to auth"
  }
}

run "passes_signing_key_type" {
  command = plan

  variables {
    agent_id = "test-agent-id"
    key_type = "signing"
  }

  assert {
    condition     = strcontains(coder_script.github_upload_public_key.script, "KEY_TYPE='signing'")
    error_message = "key_type signing should be passed to the script"
  }
}

run "passes_both_key_type" {
  command = plan

  variables {
    agent_id = "test-agent-id"
    key_type = "both"
  }

  assert {
    condition     = strcontains(coder_script.github_upload_public_key.script, "KEY_TYPE='both'")
    error_message = "key_type both should be passed to the script"
  }
}

run "rejects_invalid_key_type" {
  command = plan

  variables {
    agent_id = "test-agent-id"
    key_type = "invalid"
  }

  expect_failures = [var.key_type]
}
