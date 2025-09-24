run "plan_with_required_vars" {
  command = plan

  variables {
    agent_id = "example-agent-id"
  }

  assert {
    condition     = resource.coder_app.parsec.url == "http://localhost:8000"
    error_message = "Expected Parsec app URL to be http://localhost:8000"
  }

  assert {
    condition     = resource.coder_app.parsec.display_name == "Parsec"
    error_message = "Expected Parsec app display name to be 'Parsec'"
  }

  assert {
    condition     = resource.coder_app.parsec.slug == "parsec"
    error_message = "Expected Parsec app slug to be 'parsec'"
  }
}

run "plan_with_custom_config" {
  command = plan

  variables {
    agent_id       = "example-agent-id"
    parsec_version = "150_39b"
    server_id      = "test-server"
    peer_id        = "test-peer"
    share          = "authenticated"
    order          = 5
    group          = "Remote Desktop"
  }

  assert {
    condition     = resource.coder_app.parsec.share == "authenticated"
    error_message = "Expected Parsec app share to be 'authenticated'"
  }

  assert {
    condition     = resource.coder_app.parsec.order == 5
    error_message = "Expected Parsec app order to be 5"
  }

  assert {
    condition     = resource.coder_app.parsec.group == "Remote Desktop"
    error_message = "Expected Parsec app group to be 'Remote Desktop'"
  }
}

run "plan_with_invalid_share" {
  command = plan

  variables {
    agent_id = "example-agent-id"
    share    = "invalid"
  }

  expect_failures = [
    var.share
  ]
}

run "validate_script_template" {
  command = plan

  variables {
    agent_id       = "example-agent-id"
    parsec_version = "150_39b"
    server_id      = "custom-server"
    peer_id        = "custom-peer"
  }

  assert {
    condition = strcontains(resource.coder_script.parsec.script, "PARSEC_VERSION=150_39b")
    error_message = "Expected script to contain PARSEC_VERSION=150_39b"
  }

  assert {
    condition = strcontains(resource.coder_script.parsec.script, "SERVER_ID=custom-server")
    error_message = "Expected script to contain SERVER_ID=custom-server"
  }

  assert {
    condition = strcontains(resource.coder_script.parsec.script, "PEER_ID=custom-peer")
    error_message = "Expected script to contain PEER_ID=custom-peer"
  }
}
