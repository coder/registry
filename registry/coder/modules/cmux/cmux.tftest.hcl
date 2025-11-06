run "required_vars" {
  command = plan

  variables {
    agent_id = "foo"
  }
}

run "offline_and_use_cached_conflict" {
  command = plan

  variables {
    agent_id   = "foo"
    use_cached = true
    offline    = true
  }

  expect_failures = [
    resource.coder_script.cmux
  ]
}

run "custom_port" {
  command = plan

  variables {
    agent_id = "foo"
    port     = 8080
  }

  assert {
    condition     = resource.coder_app.cmux.url == "http://localhost:8080"
    error_message = "coder_app URL must use the configured port"
  }
}

run "custom_version" {
  command = plan

  variables {
    agent_id        = "foo"
    install_version = "0.3.0"
  }
}

# offline-only should succeed
run "offline_only_success" {
  command = plan

  variables {
    agent_id = "foo"
    offline  = true
  }
}

# use_cached-only should succeed
run "use_cached_only_success" {
  command = plan

  variables {
    agent_id   = "foo"
    use_cached = true
  }
}
