run "required_vars" {
  command = plan

  variables {
    agent_id = "foo"
  }
}

run "install_false_and_use_cached_conflict" {
  command = plan

  variables {
    agent_id   = "foo"
    use_cached = true
    install    = false
  }

  expect_failures = [
    resource.coder_script.mux
  ]
}

run "custom_port" {
  command = plan

  variables {
    agent_id = "foo"
    port     = 8080
  }

  assert {
    condition     = resource.coder_app.mux.url == "http://localhost:8080"
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

# install=false should succeed
run "install_false_only_success" {
  command = plan

  variables {
    agent_id = "foo"
    install  = false
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


